import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/meter.dart';
import '../../../domain/entities/reading.dart';
import '../../../domain/entities/supply_event.dart';
import '../../../domain/services/compliance_engine.dart';
import '../../../domain/services/forecast_engine.dart';
import '../../../domain/value_objects/units.dart';

/// All meters. Streams straight from Drift, so the UI updates from a local
/// write with no manual invalidation and never awaits a network.
final metersProvider = StreamProvider<List<Meter>>(
  (ref) => ref.watch(meterRepositoryProvider).watchAll(),
);

/// The meter currently in focus. Everything downstream is scoped to it.
class SelectedMeterId extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

final selectedMeterIdProvider =
    NotifierProvider<SelectedMeterId, String?>(SelectedMeterId.new);

final selectedMeterProvider = Provider<Meter?>((ref) {
  final meters = ref.watch(metersProvider).value ?? const <Meter>[];
  if (meters.isEmpty) return null;
  final selectedId = ref.watch(selectedMeterIdProvider);
  if (selectedId == null) return meters.first;
  return meters.where((m) => m.id == selectedId).firstOrNull ?? meters.first;
});

/// True once the user has completed onboarding — i.e. has at least one meter.
final hasMeterProvider = Provider<bool>((ref) {
  final meters = ref.watch(metersProvider);
  return (meters.value ?? const <Meter>[]).isNotEmpty;
});

final readingsProvider =
    StreamProvider.family<List<Reading>, String>((ref, meterId) {
  return ref.watch(readingRepositoryProvider).watchForMeter(meterId);
});

final purchasesProvider =
    StreamProvider.family<List<Purchase>, String>((ref, meterId) {
  return ref.watch(purchaseRepositoryProvider).watchForMeter(meterId);
});

final supplyEventsProvider =
    StreamProvider.family<List<SupplyEvent>, String>((ref, meterId) {
  return ref.watch(supplyRepositoryProvider).watchForMeter(meterId);
});

/// The rate in force for a meter: a manual override, else the bundled table.
final effectiveRateProvider = Provider.family<Rate?, String>((ref, meterId) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  if (meter == null) return null;

  final table = ref.watch(tariffTableProvider).value;
  if (table == null) return meter.rateOverride;

  return table.effectiveRate(
    disco: meter.disco,
    band: meter.tariffBand,
    override: meter.rateOverride,
  );
});

/// The prepaid depletion forecast — the product's wedge.
final balanceForecastProvider =
    Provider.family<BalanceForecast?, String>((ref, meterId) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  if (meter == null) return null;

  final readings = ref.watch(readingsProvider(meterId)).value;
  final purchases = ref.watch(purchasesProvider(meterId)).value;
  if (readings == null || purchases == null) return null;

  return ref.watch(forecastEngineProvider).balance(
        meter: meter,
        readings: readings,
        purchases: purchases,
        now: ref.watch(clockProvider)(),
      );
});

/// The postpaid cost projection to the end of the current calendar month.
final costProjectionProvider =
    Provider.family<CostProjection?, String>((ref, meterId) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  if (meter == null) return null;

  final readings = ref.watch(readingsProvider(meterId)).value;
  final purchases = ref.watch(purchasesProvider(meterId)).value;
  final rate = ref.watch(effectiveRateProvider(meterId));
  if (readings == null || purchases == null || rate == null) return null;

  final now = ref.watch(clockProvider)();
  final cycleEnd = DateTime(now.year, now.month + 1, 1);

  return ref.watch(forecastEngineProvider).cost(
        meter: meter,
        readings: readings,
        purchases: purchases,
        rate: rate,
        now: now,
        cycleEnd: cycleEnd,
      );
});

/// Band compliance over the rolling 30-day window.
final complianceProvider =
    Provider.family<ComplianceResult?, String>((ref, meterId) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  final band = meter?.tariffBand;
  if (band == null) return null;

  final events = ref.watch(supplyEventsProvider(meterId)).value;
  if (events == null) return null;

  return ref.watch(complianceEngineProvider).evaluate(
        band: band,
        events: events,
        now: ref.watch(clockProvider)(),
      );
});

/// The last seven days of supply, for the home screen strip.
final weekSupplyProvider =
    Provider.family<List<DailySupply>, String>((ref, meterId) {
  final events = ref.watch(supplyEventsProvider(meterId)).value;
  if (events == null) return const [];
  final now = ref.watch(clockProvider)();
  return ref
      .watch(complianceEngineProvider)
      .summarise(
        events: events,
        windowStart: now.subtract(const Duration(days: 6)),
        windowEnd: now,
        now: now,
      )
      .days;
});
