import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/appliance.dart';
import '../../../domain/services/consumption_engine.dart';
import '../../../domain/services/load_model_engine.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/charts/trend_chart.dart';
import '../../meter/application/meter_providers.dart';

final appliancesProvider =
    StreamProvider.family<List<Appliance>, String>((ref, meterId) {
  return ref.watch(applianceRepositoryProvider).watchForMeter(meterId);
});

/// The consumption series over a window, shared by every insight so two
/// screens cannot disagree about what a month was.
final consumptionSeriesProvider =
    Provider.family<ConsumptionSeries?, ({String meterId, int days})>(
        (ref, args) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == args.meterId)
      .firstOrNull;
  if (meter == null) return null;

  final readings = ref.watch(readingsProvider(args.meterId)).value;
  final purchases = ref.watch(purchasesProvider(args.meterId)).value;
  if (readings == null || purchases == null) return null;

  final now = ref.watch(clockProvider)();
  return ref.watch(consumptionEngineProvider).series(
        meter: meter,
        readings: readings,
        purchases: purchases,
        windowStart: now.subtract(Duration(days: args.days)),
        windowEnd: now,
      );
});

/// The trend, plotted one point per reading interval rather than per day.
///
/// A per-day series looks like a richer chart and is a worse one. Readings
/// come four to six days apart, so every daily figure is apportioned between
/// two of them — the whole line renders as estimated, the measured/modelled
/// distinction never contrasts with anything, and a signal that is always on
/// stops being a signal.
///
/// One point per interval is what was actually measured: kWh a day over a
/// span whose endpoints are both readings off the meter. Dashing is then
/// reserved for the intervals the engine really did have to estimate — a
/// prepaid period with an unrecorded purchase in it — where it means
/// something.
final consumptionTrendProvider =
    Provider.family<List<TrendPoint>, ({String meterId, int days})>(
        (ref, args) {
  final series = ref.watch(consumptionSeriesProvider(args));
  if (series == null) return const [];
  final now = ref.watch(clockProvider)();
  final from = now.subtract(Duration(days: args.days));

  return [
    for (final i in series.intervals)
      if (!i.to.isBefore(from) && i.days > 0)
        TrendPoint(
          date: i.to,
          from: i.from,
          value: i.consumed.value / i.days,
          isInterpolated: i.isEstimated,
        ),
  ];
});

/// The same series priced at the rate in force.
final costTrendProvider =
    Provider.family<List<TrendPoint>, ({String meterId, int days})>(
        (ref, args) {
  final rate = ref.watch(effectiveRateProvider(args.meterId));
  if (rate == null) return const [];
  return [
    for (final p in ref.watch(consumptionTrendProvider(args)))
      TrendPoint(
        date: p.date,
        from: p.from,
        value: rate.costOf(Kwh.fromDouble(p.value)).value,
        isInterpolated: p.isInterpolated,
      ),
  ];
});

/// Where the units go, modelled from the appliance inventory and capped by
/// the hours power was actually present.
final loadModelProvider = Provider.family<LoadModel?, String>((ref, meterId) {
  final appliances = ref.watch(appliancesProvider(meterId)).value;
  if (appliances == null) return null;

  final series =
      ref.watch(consumptionSeriesProvider((meterId: meterId, days: 30)));

  // Supply hours drive the cap: a freezer cannot run on power that was not
  // there. Where supply has not been measured well enough to say, the model
  // falls back to a full day and the screen labels the result accordingly.
  final adherenceSummary = ref.watch(weekSupplyProvider(meterId));
  final usable = adherenceSummary.where((d) => d.isUsable).toList();
  final supplyHours = usable.isEmpty
      ? 24.0
      : usable.fold<double>(0, (a, d) => a + d.hours) / usable.length;

  return ref.watch(loadModelEngineProvider).model(
        appliances: appliances,
        supplyHoursPerDay: supplyHours,
        measuredDailyTotal: series == null || !series.hasData
            ? null
            : Kwh.fromDouble(series.dailyMean),
      );
});

/// Whether the load model had measured supply hours to work from, or fell
/// back to assuming power was on all day.
final loadModelHasSupplyProvider =
    Provider.family<bool, String>((ref, meterId) {
  return ref.watch(weekSupplyProvider(meterId)).any((d) => d.isUsable);
});
