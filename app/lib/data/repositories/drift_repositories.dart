import 'package:drift/drift.dart';

import '../../domain/entities/appliance.dart';
import '../../domain/entities/dispute_case.dart';
import '../../domain/entities/generator.dart';
import '../../domain/entities/meter.dart';
import '../../domain/entities/reading.dart';
import '../../domain/entities/supply_event.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/escalation_engine.dart';
import '../../domain/value_objects/units.dart';
import '../local/database.dart';
import '../local/hlc.dart';
import '../local/mappers.dart';

/// Drift-backed repositories.
///
/// Every write goes to local storage first and the UI updates from the
/// resulting stream. Nothing here awaits a network, because there isn't one —
/// and when there is, it will write into these same tables.
class DriftMeterRepository implements MeterRepository {
  DriftMeterRepository(this._db, this._clock);

  final GridDatabase _db;
  final HlcClock _clock;

  @override
  Stream<List<Meter>> watchAll() => (_db.select(_db.meters)
        ..where((m) => m.isArchived.equals(false))
        ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
      .watch()
      .map((rows) => rows.map((r) => r.toDomain()).toList());

  @override
  Stream<Meter?> watchById(String id) =>
      (_db.select(_db.meters)..where((m) => m.id.equals(id)))
          .watchSingleOrNull()
          .map((r) => r?.toDomain());

  @override
  Future<List<Meter>> getAll() async {
    final rows = await (_db.select(_db.meters)
          ..where((m) => m.isArchived.equals(false)))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<Meter?> getById(String id) async {
    final row = await (_db.select(_db.meters)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> save(Meter meter) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.meters).insertOnConflictUpdate(
          MetersCompanion.insert(
            id: meter.id,
            label: meter.label,
            type: meter.type.name,
            disco: meter.disco.name,
            meterNumber: Value(meter.meterNumber),
            tariffBand: Value(meter.tariffBand?.name),
            rateOverrideKobo: Value(meter.rateOverride?.koboPerKwh),
            digitCount: Value(meter.digitCount),
            address: Value(meter.address),
            lga: Value(meter.lga),
            parentMeterId: Value(meter.parentMeterId),
            unitId: Value(meter.unitId),
            supplyDetectionEnabled: Value(meter.supplyDetectionEnabled),
            isArchived: Value(meter.isArchived),
            hlc: _clock.issue(now).encode(),
            createdAt: meter.createdAt.millisecondsSinceEpoch,
            updatedAt: now,
          ),
        );
  }

  @override
  Future<void> archive(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await (_db.update(_db.meters)..where((m) => m.id.equals(id))).write(
      MetersCompanion(
        isArchived: const Value(true),
        hlc: Value(_clock.issue(now).encode()),
        updatedAt: Value(now),
      ),
    );
  }
}

class DriftReadingRepository implements ReadingRepository {
  DriftReadingRepository(this._db, this._clock);

  final GridDatabase _db;
  final HlcClock _clock;

  @override
  Stream<List<Reading>> watchForMeter(String meterId) =>
      (_db.select(_db.readings)
            ..where((r) => r.meterId.equals(meterId))
            ..orderBy([(r) => OrderingTerm.desc(r.readAt)]))
          .watch()
          .map((rows) => rows.map((r) => r.toDomain()).toList());

  @override
  Future<List<Reading>> getForMeter(String meterId) async {
    final rows = await (_db.select(_db.readings)
          ..where((r) => r.meterId.equals(meterId))
          ..orderBy([(r) => OrderingTerm.desc(r.readAt)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<Reading?> latestForMeter(String meterId) async {
    final row = await (_db.select(_db.readings)
          ..where((r) =>
              r.meterId.equals(meterId) & r.supersededById.isNull())
          ..orderBy([(r) => OrderingTerm.desc(r.readAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> add(Reading reading) => _insert(reading);

  @override
  Future<void> supersede({
    required String originalId,
    required Reading correction,
  }) async {
    // A correction is additive. The original row keeps its value, its photo
    // and its timestamp; it simply gains a pointer to what replaced it.
    await _db.transaction(() async {
      await _insert(correction);
      await (_db.update(_db.readings)..where((r) => r.id.equals(originalId)))
          .write(ReadingsCompanion(supersededById: Value(correction.id)));
    });
  }

  Future<void> _insert(Reading reading) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.readings).insert(
          ReadingsCompanion.insert(
            id: reading.id,
            meterId: reading.meterId,
            valueMilli: reading.value.milli,
            readAt: reading.readAt.millisecondsSinceEpoch,
            recordedAt: reading.recordedAt.millisecondsSinceEpoch,
            hlc: _clock.issue(now).encode(),
            source: reading.source.name,
            ocrConfidence: Value(reading.ocrConfidence),
            photoPath: Value(reading.photoPath),
            photoSha256: Value(reading.photoSha256),
            flags: Value(reading.flags),
            supersededById: Value(reading.supersededById),
            note: Value(reading.note),
          ),
        );
  }
}

class DriftPurchaseRepository implements PurchaseRepository {
  DriftPurchaseRepository(this._db, this._clock);

  final GridDatabase _db;
  final HlcClock _clock;

  @override
  Stream<List<Purchase>> watchForMeter(String meterId) =>
      (_db.select(_db.purchases)
            ..where((p) => p.meterId.equals(meterId))
            ..orderBy([(p) => OrderingTerm.desc(p.purchasedAt)]))
          .watch()
          .map((rows) => rows.map((r) => r.toDomain()).toList());

  @override
  Future<List<Purchase>> getForMeter(String meterId) async {
    final rows = await (_db.select(_db.purchases)
          ..where((p) => p.meterId.equals(meterId))
          ..orderBy([(p) => OrderingTerm.desc(p.purchasedAt)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<void> add(Purchase purchase) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.purchases).insert(
          PurchasesCompanion.insert(
            id: purchase.id,
            meterId: purchase.meterId,
            amountKobo: purchase.amount.kobo,
            unitsMilli: Value(purchase.units?.milli),
            unitsDerived: Value(purchase.unitsDerived),
            effectiveRateKobo: Value(purchase.effectiveRate?.koboPerKwh),
            purchasedAt: purchase.purchasedAt.millisecondsSinceEpoch,
            tokenRef: Value(purchase.tokenRef),
            hlc: _clock.issue(now).encode(),
          ),
        );
  }
}

class DriftSupplyRepository implements SupplyRepository {
  DriftSupplyRepository(this._db, this._clock);

  final GridDatabase _db;
  final HlcClock _clock;

  @override
  Stream<List<SupplyEvent>> watchForMeter(String meterId) =>
      (_db.select(_db.supplyEvents)
            ..where((e) => e.meterId.equals(meterId))
            ..orderBy([(e) => OrderingTerm.desc(e.startedAt)]))
          .watch()
          .map((rows) => rows.map((r) => r.toDomain()).toList());

  @override
  Future<List<SupplyEvent>> getForMeter(String meterId) async {
    final rows = await (_db.select(_db.supplyEvents)
          ..where((e) => e.meterId.equals(meterId))
          ..orderBy([(e) => OrderingTerm.desc(e.startedAt)]))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<SupplyEvent?> ongoingForMeter(String meterId) async {
    final row = await (_db.select(_db.supplyEvents)
          ..where((e) =>
              e.meterId.equals(meterId) &
              e.endedAt.isNull() &
              e.supersededById.isNull())
          ..orderBy([(e) => OrderingTerm.desc(e.startedAt)])
          ..limit(1))
        .getSingleOrNull();
    return row?.toDomain();
  }

  @override
  Future<void> add(SupplyEvent event) => _insert(event);

  @override
  Future<void> close({
    required String id,
    required DateTime endedAt,
  }) async {
    await (_db.update(_db.supplyEvents)..where((e) => e.id.equals(id))).write(
      SupplyEventsCompanion(
        endedAt: Value(endedAt.millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> supersede({
    required String originalId,
    required SupplyEvent replacement,
  }) async {
    await _db.transaction(() async {
      await _insert(replacement);
      await (_db.update(_db.supplyEvents)
            ..where((e) => e.id.equals(originalId)))
          .write(SupplyEventsCompanion(
        supersededById: Value(replacement.id),
      ));
    });
  }

  Future<void> _insert(SupplyEvent event) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.supplyEvents).insert(
          SupplyEventsCompanion.insert(
            id: event.id,
            meterId: event.meterId,
            state: event.state.name,
            startedAt: event.startedAt.millisecondsSinceEpoch,
            endedAt: Value(event.endedAt?.millisecondsSinceEpoch),
            source: event.source.name,
            platformCapability: event.platformCapability.name,
            note: Value(event.note),
            supersededById: Value(event.supersededById),
            hlc: _clock.issue(now).encode(),
          ),
        );
  }
}

class DriftDisputeCaseRepository implements DisputeCaseRepository {
  DriftDisputeCaseRepository(this._db, this._clock);

  final GridDatabase _db;
  final HlcClock _clock;

  @override
  Stream<List<DisputeCase>> watchForMeter(String meterId) =>
      (_db.select(_db.disputeCases)
            ..where((c) => c.meterId.equals(meterId))
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
          .watch()
          .map((rows) => rows.map(_toDomain).toList());

  @override
  Future<List<DisputeCase>> getForMeter(String meterId) async {
    final rows = await (_db.select(_db.disputeCases)
          ..where((c) => c.meterId.equals(meterId))
          ..orderBy([(c) => OrderingTerm.desc(c.createdAt)]))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<void> save(DisputeCase c) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.disputeCases).insertOnConflictUpdate(
          DisputeCasesCompanion.insert(
            id: c.id,
            meterId: c.meterId,
            kind: c.kind,
            step: c.step.name,
            status: c.status.name,
            periodStart: c.periodStart.millisecondsSinceEpoch,
            periodEnd: c.periodEnd.millisecondsSinceEpoch,
            submittedAt: Value(c.submittedAt?.millisecondsSinceEpoch),
            reference: Value(c.reference),
            notes: Value(c.notes),
            packPath: Value(c.packPath),
            createdAt: c.createdAt.millisecondsSinceEpoch,
            hlc: _clock.issue(now).encode(),
          ),
        );
  }

  @override
  Future<void> remove(String id) =>
      (_db.delete(_db.disputeCases)..where((c) => c.id.equals(id))).go();

  DisputeCase _toDomain(DisputeCaseRow r) => DisputeCase(
        id: r.id,
        meterId: r.meterId,
        kind: r.kind,
        step: EscalationStep.values.firstWhere(
          (s) => s.name == r.step,
          orElse: () => EscalationStep.businessUnit,
        ),
        status: CaseStatus.values.firstWhere(
          (s) => s.name == r.status,
          orElse: () => CaseStatus.open,
        ),
        periodStart: DateTime.fromMillisecondsSinceEpoch(r.periodStart),
        periodEnd: DateTime.fromMillisecondsSinceEpoch(r.periodEnd),
        submittedAt: r.submittedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r.submittedAt!),
        reference: r.reference,
        notes: r.notes,
        packPath: r.packPath,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
      );
}

class DriftGeneratorRepository implements GeneratorRepository {
  DriftGeneratorRepository(this._db, this._clock);

  final GridDatabase _db;
  final HlcClock _clock;

  String _hlc() => _clock.issue(DateTime.now().millisecondsSinceEpoch).encode();

  // --- the sets -------------------------------------------------------------

  @override
  Stream<List<Generator>> watchGenerators(String meterId) =>
      (_db.select(_db.generators)..where((g) => g.meterId.equals(meterId)))
          .watch()
          .map((rows) => rows.map(_toGenerator).toList());

  @override
  Future<List<Generator>> getGenerators(String meterId) async {
    final rows = await (_db.select(_db.generators)
          ..where((g) => g.meterId.equals(meterId)))
        .get();
    return rows.map(_toGenerator).toList();
  }

  @override
  Future<void> saveGenerator(Generator g) =>
      _db.into(_db.generators).insertOnConflictUpdate(
            GeneratorsCompanion.insert(
              id: g.id,
              meterId: g.meterId,
              name: g.name,
              ratedKva: g.ratedKva,
              litresPerHour: g.litresPerHour,
              fuel: Value(g.fuel.name),
              hlc: _hlc(),
            ),
          );

  @override
  Future<void> removeGenerator(String id) =>
      (_db.delete(_db.generators)..where((g) => g.id.equals(id))).go();

  // --- fuel -----------------------------------------------------------------

  @override
  Stream<List<FuelPurchase>> watchFuel(String meterId) =>
      (_db.select(_db.fuelPurchases)
            ..where((f) => f.meterId.equals(meterId))
            ..orderBy([(f) => OrderingTerm.desc(f.purchasedAt)]))
          .watch()
          .map((rows) => rows.map(_toFuel).toList());

  @override
  Future<List<FuelPurchase>> getFuel(String meterId) async {
    final rows = await (_db.select(_db.fuelPurchases)
          ..where((f) => f.meterId.equals(meterId))
          ..orderBy([(f) => OrderingTerm.desc(f.purchasedAt)]))
        .get();
    return rows.map(_toFuel).toList();
  }

  /// Append only. A fuel purchase is a fact, so there is no update path here
  /// and no delete — the same rule the readings live under.
  @override
  Future<void> addFuel(FuelPurchase p) =>
      _db.into(_db.fuelPurchases).insert(
            FuelPurchasesCompanion.insert(
              id: p.id,
              meterId: p.meterId,
              generatorId: Value(p.generatorId),
              litres: p.litres,
              amountKobo: p.amount.kobo,
              purchasedAt: p.purchasedAt.millisecondsSinceEpoch,
              hlc: _hlc(),
            ),
          );

  // --- runs -----------------------------------------------------------------

  @override
  Stream<List<GeneratorRun>> watchRuns(String meterId) =>
      (_db.select(_db.generatorRuns)
            ..where((r) => r.meterId.equals(meterId))
            ..orderBy([(r) => OrderingTerm.desc(r.startedAt)]))
          .watch()
          .map((rows) => rows.map(_toRun).toList());

  @override
  Future<List<GeneratorRun>> getRuns(String meterId) async {
    final rows = await (_db.select(_db.generatorRuns)
          ..where((r) => r.meterId.equals(meterId))
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)]))
        .get();
    return rows.map(_toRun).toList();
  }

  @override
  Future<void> startRun(GeneratorRun run) =>
      _db.into(_db.generatorRuns).insert(
            GeneratorRunsCompanion.insert(
              id: run.id,
              meterId: run.meterId,
              generatorId: Value(run.generatorId),
              startedAt: run.startedAt.millisecondsSinceEpoch,
              endedAt: Value(run.endedAt?.millisecondsSinceEpoch),
              hlc: _hlc(),
            ),
          );

  /// Closing a run writes an end time onto an open row rather than replacing
  /// it — the guard on `endedAt` being null means a second tap on "stopped"
  /// cannot shorten a run that was already closed.
  @override
  Future<void> endRun({required String id, required DateTime endedAt}) async {
    await (_db.update(_db.generatorRuns)
          ..where((r) => r.id.equals(id) & r.endedAt.isNull()))
        .write(
      GeneratorRunsCompanion(
        endedAt: Value(endedAt.millisecondsSinceEpoch),
        hlc: Value(_hlc()),
      ),
    );
  }

  @override
  Future<GeneratorRun?> ongoingRun(String meterId) async {
    final row = await (_db.select(_db.generatorRuns)
          ..where((r) => r.meterId.equals(meterId) & r.endedAt.isNull())
          ..orderBy([(r) => OrderingTerm.desc(r.startedAt)])
          ..limit(1))
        .getSingleOrNull();
    return row == null ? null : _toRun(row);
  }

  // --- mapping --------------------------------------------------------------

  Generator _toGenerator(GeneratorRow r) => Generator(
        id: r.id,
        meterId: r.meterId,
        name: r.name,
        ratedKva: r.ratedKva,
        litresPerHour: r.litresPerHour,
        fuel: FuelType.values.firstWhere(
          (f) => f.name == r.fuel,
          orElse: () => FuelType.petrol,
        ),
      );

  FuelPurchase _toFuel(FuelPurchaseRow r) => FuelPurchase(
        id: r.id,
        meterId: r.meterId,
        generatorId: r.generatorId,
        litres: r.litres,
        amount: Naira.fromKobo(r.amountKobo),
        purchasedAt: DateTime.fromMillisecondsSinceEpoch(r.purchasedAt),
      );

  GeneratorRun _toRun(GeneratorRunRow r) => GeneratorRun(
        id: r.id,
        meterId: r.meterId,
        generatorId: r.generatorId,
        startedAt: DateTime.fromMillisecondsSinceEpoch(r.startedAt),
        endedAt: r.endedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r.endedAt!),
      );
}

class DriftApplianceRepository implements ApplianceRepository {
  DriftApplianceRepository(this._db, this._clock);

  final GridDatabase _db;
  final HlcClock _clock;

  @override
  Stream<List<Appliance>> watchForMeter(String meterId) =>
      (_db.select(_db.appliances)..where((a) => a.meterId.equals(meterId)))
          .watch()
          .map((rows) => rows.map((r) => r.toDomain()).toList());

  @override
  Future<List<Appliance>> getForMeter(String meterId) async {
    final rows = await (_db.select(_db.appliances)
          ..where((a) => a.meterId.equals(meterId)))
        .get();
    return rows.map((r) => r.toDomain()).toList();
  }

  @override
  Future<void> save(Appliance appliance) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.into(_db.appliances).insertOnConflictUpdate(
          AppliancesCompanion.insert(
            id: appliance.id,
            meterId: Value(appliance.meterId),
            unitId: Value(appliance.unitId),
            catalogueKey: Value(appliance.catalogueKey),
            name: appliance.name,
            ratedWatts: appliance.ratedWatts,
            quantity: Value(appliance.quantity),
            hoursPerDay: appliance.hoursPerDay,
            mainsOnly: Value(appliance.mainsOnly),
            hlc: _clock.issue(now).encode(),
          ),
        );
  }

  @override
  Future<void> remove(String id) =>
      (_db.delete(_db.appliances)..where((a) => a.id.equals(id))).go();
}

class DriftSettingsRepository implements SettingsRepository {
  DriftSettingsRepository(this._db);

  final GridDatabase _db;

  @override
  Future<String?> get(String key) async {
    final row = await (_db.select(_db.appSettings)
          ..where((s) => s.key.equals(key)))
        .getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> set(String key, String value) async {
    await _db.into(_db.appSettings).insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: key,
            value: value,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Stream<String?> watch(String key) =>
      (_db.select(_db.appSettings)..where((s) => s.key.equals(key)))
          .watchSingleOrNull()
          .map((r) => r?.value);
}
