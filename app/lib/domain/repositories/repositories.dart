import '../entities/appliance.dart';
import '../entities/dispute_case.dart';
import '../entities/meter.dart';
import '../entities/reading.dart';
import '../entities/supply_event.dart';

/// Repository contracts.
///
/// These live in the domain layer and are implemented in the data layer
/// against Drift. When a server eventually arrives it is added as a *second
/// source behind these same interfaces*, not as a replacement — so no
/// presentation code changes when sync ships.
abstract interface class MeterRepository {
  Stream<List<Meter>> watchAll();
  Stream<Meter?> watchById(String id);
  Future<List<Meter>> getAll();
  Future<Meter?> getById(String id);
  Future<void> save(Meter meter);
  Future<void> archive(String id);
}

abstract interface class ReadingRepository {
  Stream<List<Reading>> watchForMeter(String meterId);
  Future<List<Reading>> getForMeter(String meterId);
  Future<Reading?> latestForMeter(String meterId);
  Future<void> add(Reading reading);

  /// Corrections are additive: this writes a new reading and marks the
  /// original superseded. The original always survives, because a record
  /// that can be silently rewritten is not evidence.
  Future<void> supersede({
    required String originalId,
    required Reading correction,
  });
}

abstract interface class PurchaseRepository {
  Stream<List<Purchase>> watchForMeter(String meterId);
  Future<List<Purchase>> getForMeter(String meterId);
  Future<void> add(Purchase purchase);
}

abstract interface class SupplyRepository {
  Stream<List<SupplyEvent>> watchForMeter(String meterId);
  Future<List<SupplyEvent>> getForMeter(String meterId);
  Future<SupplyEvent?> ongoingForMeter(String meterId);
  Future<void> add(SupplyEvent event);
  Future<void> close({required String id, required DateTime endedAt});

  /// A manual entry supersedes an inferred one for an overlapping period
  /// rather than editing it, so the original inference stays auditable.
  Future<void> supersede({
    required String originalId,
    required SupplyEvent replacement,
  });
}

abstract interface class ApplianceRepository {
  Stream<List<Appliance>> watchForMeter(String meterId);
  Future<List<Appliance>> getForMeter(String meterId);
  Future<void> save(Appliance appliance);
  Future<void> remove(String id);
}

abstract interface class DisputeCaseRepository {
  Stream<List<DisputeCase>> watchForMeter(String meterId);
  Future<List<DisputeCase>> getForMeter(String meterId);
  Future<void> save(DisputeCase c);
  Future<void> remove(String id);
}

abstract interface class SettingsRepository {
  Future<String?> get(String key);
  Future<void> set(String key, String value);
  Stream<String?> watch(String key);
}
