import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/meter.dart';
import '../../../domain/entities/reading.dart';
import '../../../domain/entities/supply_event.dart';
import '../../../domain/services/band_adherence_engine.dart';
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

/// What the band shortfall is worth, in naira. Feature F4.
///
/// Returns null only when there is nothing to evaluate at all — no meter, no
/// band, no rate. A partly-observed month returns [AdherenceUnknown], which
/// is a result the UI is required to render rather than a gap it may skip.
final bandAdherenceProvider =
    Provider.family<BandAdherence?, String>((ref, meterId) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  final band = meter?.tariffBand;
  if (meter == null || band == null) return null;

  final billedRate = ref.watch(effectiveRateProvider(meterId));
  if (billedRate == null) return null;

  final events = ref.watch(supplyEventsProvider(meterId)).value;
  final readings = ref.watch(readingsProvider(meterId)).value;
  final purchases = ref.watch(purchasesProvider(meterId)).value;
  if (events == null || readings == null || purchases == null) return null;

  final table = ref.watch(tariffTableProvider).value;
  final now = ref.watch(clockProvider)();
  const windowDays = 30;
  final windowStart = now.subtract(const Duration(days: windowDays));

  final summary = ref.watch(complianceEngineProvider).summarise(
        events: events,
        windowStart: windowStart,
        windowEnd: now,
        now: now,
      );

  // Energy over the same window the hours were measured over — `totalIn`,
  // not `total`. A valuation that multiplies one period's rate difference by
  // the whole history's energy is a number nobody can defend, and it is not
  // obviously wrong on screen: it just reads as a bigger claim.
  final series = ref.watch(consumptionEngineProvider).series(
        meter: meter,
        readings: readings,
        purchases: purchases,
        windowStart: windowStart,
        windowEnd: now,
      );

  return ref.watch(bandAdherenceEngineProvider).evaluate(
        billedBand: band,
        summary: summary,
        energy: series.totalIn(windowStart, now),
        energyIsAllocated: series.isInterpolatedIn(windowStart, now),
        billedRate: billedRate,
        rateForBand: (b) => table?.rateFor(meter.disco, b),
        windowDays: windowDays,
      );
});
