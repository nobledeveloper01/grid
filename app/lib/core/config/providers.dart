import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../data/assets/appliance_catalogue.dart';
import '../../data/assets/tariff_table.dart';
import '../../data/local/database.dart';
import '../../data/local/hlc.dart';
import '../../data/repositories/drift_repositories.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/band_adherence_engine.dart';
import '../../domain/services/compliance_engine.dart';
import '../../domain/services/escalation_engine.dart';
import '../../domain/services/consumption_engine.dart';
import '../../domain/services/forecast_engine.dart';
import '../../domain/services/load_model_engine.dart';
import '../../domain/services/supply_inference_engine.dart';
import '../../domain/services/validation_engine.dart';
import '../platform/supply_monitor.dart';
import '../platform/text_recogniser.dart';

/// Composition root.
///
/// Riverpod is the only container — there is no second DI framework. Every
/// provider here is overridable in tests, which is the main reason the
/// engines take their collaborators by constructor.

// --- Infrastructure ---------------------------------------------------------

final uuidProvider = Provider<Uuid>((ref) => const Uuid());

/// The wall clock, injected rather than called directly, so time-dependent
/// code is deterministic under test.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Overridden during bootstrap'),
);

/// This device's stable identifier, used as the HLC node id so concurrent
/// writes from two devices break ties deterministically.
final nodeIdProvider = Provider<String>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  const key = 'grid.node_id';
  final existing = prefs.getString(key);
  if (existing != null) return existing;
  final generated = ref.watch(uuidProvider).v4().replaceAll('-', '').substring(0, 12);
  prefs.setString(key, generated);
  return generated;
});

final databaseProvider = Provider<GridDatabase>((ref) {
  final db = GridDatabase();
  ref.onDispose(db.close);
  return db;
});

final hlcClockProvider = Provider<HlcClock>(
  (ref) => HlcClock(nodeId: ref.watch(nodeIdProvider)),
);

// --- Reference data ---------------------------------------------------------

final tariffTableProvider = FutureProvider<TariffTable>(
  (ref) => TariffTable.load(),
);

final applianceCatalogueProvider = FutureProvider<ApplianceCatalogue>(
  (ref) => ApplianceCatalogue.load(),
);

// --- Repositories -----------------------------------------------------------

final meterRepositoryProvider = Provider<MeterRepository>(
  (ref) => DriftMeterRepository(
    ref.watch(databaseProvider),
    ref.watch(hlcClockProvider),
  ),
);

final readingRepositoryProvider = Provider<ReadingRepository>(
  (ref) => DriftReadingRepository(
    ref.watch(databaseProvider),
    ref.watch(hlcClockProvider),
  ),
);

final purchaseRepositoryProvider = Provider<PurchaseRepository>(
  (ref) => DriftPurchaseRepository(
    ref.watch(databaseProvider),
    ref.watch(hlcClockProvider),
  ),
);

final supplyRepositoryProvider = Provider<SupplyRepository>(
  (ref) => DriftSupplyRepository(
    ref.watch(databaseProvider),
    ref.watch(hlcClockProvider),
  ),
);

final applianceRepositoryProvider = Provider<ApplianceRepository>(
  (ref) => DriftApplianceRepository(
    ref.watch(databaseProvider),
    ref.watch(hlcClockProvider),
  ),
);

final generatorRepositoryProvider = Provider<GeneratorRepository>(
  (ref) => DriftGeneratorRepository(
    ref.watch(databaseProvider),
    ref.watch(hlcClockProvider),
  ),
);

final disputeCaseRepositoryProvider = Provider<DisputeCaseRepository>(
  (ref) => DriftDisputeCaseRepository(
    ref.watch(databaseProvider),
    ref.watch(hlcClockProvider),
  ),
);

final escalationEngineProvider =
    Provider<EscalationEngine>((ref) => const EscalationEngine());

final settingsRepositoryProvider = Provider<SettingsRepository>(
  (ref) => DriftSettingsRepository(ref.watch(databaseProvider)),
);

// --- Engines ----------------------------------------------------------------
//
// Pure, const, stateless. They exist as providers only so tests can swap in
// a differently-configured instance.

final consumptionEngineProvider =
    Provider<ConsumptionEngine>((ref) => const ConsumptionEngine());

final forecastEngineProvider = Provider<ForecastEngine>(
  (ref) => ForecastEngine(consumption: ref.watch(consumptionEngineProvider)),
);

final validationEngineProvider =
    Provider<ValidationEngine>((ref) => const ValidationEngine());

final complianceEngineProvider =
    Provider<ComplianceEngine>((ref) => const ComplianceEngine());

final bandAdherenceEngineProvider =
    Provider<BandAdherenceEngine>((ref) => const BandAdherenceEngine());

final loadModelEngineProvider =
    Provider<LoadModelEngine>((ref) => const LoadModelEngine());

// --- Platform ---------------------------------------------------------------

/// On-device OCR. Null until a per-platform engine is wired in; the capture
/// flow checks [TextRecogniser.isAvailable] and routes to manual entry when
/// it reports false. See core/platform/text_recogniser.dart for why this is
/// a façade rather than a direct ML Kit dependency.
final textRecogniserProvider =
    Provider<TextRecogniser>((ref) => const PlatformTextRecogniser());

/// Device power monitoring. Reports honestly what the platform can promise.
final supplyMonitorProvider =
    Provider<SupplyMonitor>((ref) => PlatformSupplyMonitor());

final supplyInferenceEngineProvider =
    Provider<SupplyInferenceEngine>((ref) => const SupplyInferenceEngine());

/// Whether the camera path should be offered at all. The capture screen hides
/// it rather than showing a button that fails.
final ocrAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(textRecogniserProvider).isAvailable,
);
