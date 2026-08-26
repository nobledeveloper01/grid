import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/generator.dart';
import '../../../domain/services/generator_engine.dart';
import '../../../domain/services/load_model_engine.dart';
import '../../../domain/services/solar_sizing_engine.dart';
import '../../../domain/value_objects/units.dart';
import '../../insights/application/insights_providers.dart';
import '../../meter/application/meter_providers.dart';

final generatorEngineProvider =
    Provider<GeneratorEngine>((ref) => const GeneratorEngine());

final solarSizingEngineProvider =
    Provider<SolarSizingEngine>((ref) => const SolarSizingEngine());

final generatorsProvider =
    StreamProvider.family<List<Generator>, String>((ref, meterId) {
  return ref.watch(generatorRepositoryProvider).watchGenerators(meterId);
});

final fuelProvider =
    StreamProvider.family<List<FuelPurchase>, String>((ref, meterId) {
  return ref.watch(generatorRepositoryProvider).watchFuel(meterId);
});

final runsProvider =
    StreamProvider.family<List<GeneratorRun>, String>((ref, meterId) {
  return ref.watch(generatorRepositoryProvider).watchRuns(meterId);
});

/// The run still going, if any. Derived from the stream rather than queried,
/// so the button that stops it updates the instant the row is written.
final ongoingRunProvider =
    Provider.family<GeneratorRun?, String>((ref, meterId) {
  final runs = ref.watch(runsProvider(meterId)).value;
  return runs?.where((r) => r.isRunning).firstOrNull;
});

/// The window every economics figure is computed over. One constant, because
/// pricing fuel from one window against running from another is the mistake
/// this whole feature is most exposed to.
const economicsWindowDays = 30;

final generatorCostProvider =
    Provider.family<GeneratorCost, String>((ref, meterId) {
  final runs = ref.watch(runsProvider(meterId)).value ?? const [];
  final fuel = ref.watch(fuelProvider(meterId)).value ?? const [];
  final sets = ref.watch(generatorsProvider(meterId)).value ?? const [];
  final now = ref.watch(clockProvider)();

  return ref.watch(generatorEngineProvider).cost(
        runs: runs,
        fuel: fuel,
        generators: sets,
        from: now.subtract(const Duration(days: economicsWindowDays)),
        to: now,
        now: now,
      );
});

/// Grid and generator side by side. Null when either half is missing — there
/// is no honest blend of one source.
final blendedCostProvider =
    Provider.family<BlendedCost?, String>((ref, meterId) {
  final generator = ref.watch(generatorCostProvider(meterId));
  if (generator is! GeneratorCostKnown) return null;

  final rate = ref.watch(effectiveRateProvider(meterId));
  if (rate == null) return null;

  final series = ref.watch(
    consumptionSeriesProvider(
      (meterId: meterId, days: economicsWindowDays),
    ),
  );
  if (series == null || !series.hasData) return null;

  return ref.watch(generatorEngineProvider).blend(
        gridEnergy: series.total,
        gridRate: rate,
        generator: generator,
      );
});

/// What the household spends on fuel in a month, measured. Feeds the solar
/// payback, which is deliberately absent without it.
final monthlyFuelSpendProvider =
    Provider.family<Naira?, String>((ref, meterId) {
  final fuel = ref.watch(fuelProvider(meterId)).value;
  if (fuel == null || fuel.isEmpty) return null;
  final now = ref.watch(clockProvider)();
  final from = now.subtract(const Duration(days: economicsWindowDays));
  final inWindow = fuel.where((f) => !f.purchasedAt.isBefore(from));
  if (inWindow.isEmpty) return null;
  return inWindow.fold<Naira>(Naira.zero, (a, f) => a + f.amount);
});

final solarSizingProvider =
    Provider.family<SolarSizing, String>((ref, meterId) {
  final now = ref.watch(clockProvider)();
  final from = now.subtract(const Duration(days: economicsWindowDays));

  final series = ref.watch(
    consumptionSeriesProvider(
      (meterId: meterId, days: economicsWindowDays),
    ),
  );
  final events = ref.watch(supplyEventsProvider(meterId)).value ?? const [];
  final compliance = ref.watch(complianceEngineProvider);

  final summary = compliance.summarise(
    events: events,
    windowStart: from,
    windowEnd: now,
    now: now,
  );

  return ref.watch(solarSizingEngineProvider).size(
        dailyKwh: Kwh.fromDouble(series?.dailyMean ?? 0),
        longestOutageHours: compliance.longestOutageHours(
          events: events,
          windowStart: from,
          windowEnd: now,
        ),
        meanOutageHoursPerDay: 24 - summary.rollingAverageHours,
        daysMeasured: summary.usableDayCount,
        coverage: summary.coverage,
        monthlyGeneratorSpend: ref.watch(monthlyFuelSpendProvider(meterId)),
      );
});

/// Every appliance priced for a month, pegged to the meter.
final applianceCoachProvider =
    Provider.family<List<ApplianceCost>, String>((ref, meterId) {
  final model = ref.watch(loadModelProvider(meterId));
  final rate = ref.watch(effectiveRateProvider(meterId));
  if (model == null || rate == null) return const [];
  return ref.watch(loadModelEngineProvider).coach(model: model, rate: rate);
});

class GeneratorController extends Notifier<void> {
  @override
  void build() {}

  Future<void> saveSet({
    required String meterId,
    required String name,
    required double ratedKva,
    required double litresPerHour,
    FuelType fuel = FuelType.petrol,
    String? existingId,
  }) =>
      ref.read(generatorRepositoryProvider).saveGenerator(
            Generator(
              id: existingId ?? ref.read(uuidProvider).v7(),
              meterId: meterId,
              name: name,
              ratedKva: ratedKva,
              litresPerHour: litresPerHour,
              fuel: fuel,
            ),
          );

  Future<void> logFuel({
    required String meterId,
    required double litres,
    required Naira amount,
  }) =>
      ref.read(generatorRepositoryProvider).addFuel(
            FuelPurchase(
              id: ref.read(uuidProvider).v7(),
              meterId: meterId,
              litres: litres,
              amount: amount,
              purchasedAt: ref.read(clockProvider)(),
            ),
          );

  /// Starts a run, unless one is already going. Two open runs would double
  /// every hour the household is charged for.
  Future<void> start(String meterId) async {
    final repo = ref.read(generatorRepositoryProvider);
    if (await repo.ongoingRun(meterId) != null) return;
    await repo.startRun(
      GeneratorRun(
        id: ref.read(uuidProvider).v7(),
        meterId: meterId,
        startedAt: ref.read(clockProvider)(),
      ),
    );
  }

  Future<void> stop(String meterId) async {
    final repo = ref.read(generatorRepositoryProvider);
    final open = await repo.ongoingRun(meterId);
    if (open == null) return;
    await repo.endRun(id: open.id, endedAt: ref.read(clockProvider)());
  }
}

final generatorControllerProvider =
    NotifierProvider<GeneratorController, void>(GeneratorController.new);
