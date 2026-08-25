import 'package:drift/drift.dart';

/// Metering points. Mutable state: resolved last-writer-wins on the hybrid
/// logical clock when sync arrives.
@DataClassName('MeterRow')
class Meters extends Table {
  TextColumn get id => text()();
  TextColumn get label => text()();
  TextColumn get type => text()();
  TextColumn get disco => text()();
  TextColumn get meterNumber => text().nullable()();
  TextColumn get tariffBand => text().nullable()();
  IntColumn get rateOverrideKobo => integer().nullable()();
  IntColumn get digitCount => integer().nullable()();
  TextColumn get address => text().nullable()();
  TextColumn get lga => text().nullable()();
  TextColumn get parentMeterId => text().nullable()();
  TextColumn get unitId => text().nullable()();
  BoolColumn get supplyDetectionEnabled =>
      boolean().withDefault(const Constant(true))();
  BoolColumn get isArchived => boolean().withDefault(const Constant(false))();

  /// Hybrid logical clock stamp. Written from day one even though nothing
  /// consumes it yet — retrofitting causal ordering onto existing rows is
  /// painful, and an unused column is free.
  TextColumn get hlc => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Meter readings. **A fact**: append-only, never updated, never deleted.
/// Corrections write a new row pointing at this one via [supersededById].
@DataClassName('ReadingRow')
class Readings extends Table {
  TextColumn get id => text()();
  TextColumn get meterId => text().references(Meters, #id)();

  /// Reading x 1000. Integers only — floats would introduce rounding drift
  /// into the arithmetic a dispute pack depends on.
  IntColumn get valueMilli => integer()();

  /// When the meter was actually read.
  IntColumn get readAt => integer()();

  /// When the row was written.
  IntColumn get recordedAt => integer()();

  TextColumn get hlc => text()();
  TextColumn get source => text()();
  RealColumn get ocrConfidence => real().nullable()();
  TextColumn get ocrRawText => text().nullable()();

  /// App-private path. Never a blob — that would destroy query performance
  /// and backup size.
  TextColumn get photoPath => text().nullable()();
  TextColumn get photoSha256 => text().nullable()();
  BoolColumn get photoUploaded =>
      boolean().withDefault(const Constant(false))();

  IntColumn get flags => integer().withDefault(const Constant(0))();
  TextColumn get supersededById => text().nullable()();
  TextColumn get note => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Prepaid unit purchases. Also a fact.
@DataClassName('PurchaseRow')
class Purchases extends Table {
  TextColumn get id => text()();
  TextColumn get meterId => text().references(Meters, #id)();
  IntColumn get amountKobo => integer()();
  IntColumn get unitsMilli => integer().nullable()();
  BoolColumn get unitsDerived =>
      boolean().withDefault(const Constant(false))();
  IntColumn get effectiveRateKobo => integer().nullable()();
  IntColumn get purchasedAt => integer()();
  TextColumn get tokenRef => text().nullable()();
  TextColumn get hlc => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Supply availability periods. A fact.
@DataClassName('SupplyEventRow')
class SupplyEvents extends Table {
  TextColumn get id => text()();
  TextColumn get meterId => text().references(Meters, #id)();
  TextColumn get state => text()();
  IntColumn get startedAt => integer()();
  IntColumn get endedAt => integer().nullable()();
  TextColumn get source => text()();

  /// What the platform could promise when this was recorded. Stored per
  /// event, not per device, because it changes — and a dispute pack spanning
  /// the change must report coverage honestly on both sides of it.
  TextColumn get platformCapability => text()();

  TextColumn get note => text().nullable()();
  TextColumn get supersededById => text().nullable()();
  TextColumn get hlc => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Appliance inventory. Mutable state.
@DataClassName('ApplianceRow')
class Appliances extends Table {
  TextColumn get id => text()();
  TextColumn get meterId => text().nullable().references(Meters, #id)();
  TextColumn get unitId => text().nullable()();
  TextColumn get catalogueKey => text().nullable()();
  TextColumn get name => text()();
  IntColumn get ratedWatts => integer()();
  IntColumn get quantity => integer().withDefault(const Constant(1))();
  RealColumn get hoursPerDay => real()();
  BoolColumn get mainsOnly => boolean().withDefault(const Constant(true))();
  TextColumn get hlc => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Billing cycles, and the DisCo's own figures for them — which is what a
/// dispute is ultimately contesting.
@DataClassName('BillingCycleRow')
class BillingCycles extends Table {
  TextColumn get id => text()();
  TextColumn get meterId => text().references(Meters, #id)();
  IntColumn get periodStart => integer()();
  IntColumn get periodEnd => integer()();
  IntColumn get billedAmountKobo => integer().nullable()();
  IntColumn get billedUnitsMilli => integer().nullable()();
  TextColumn get billPhotoPath => text().nullable()();
  BoolColumn get isDisputed => boolean().withDefault(const Constant(false))();
  TextColumn get hlc => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Durable mutation queue.
///
/// Exists from day one even though there is no server to drain to yet. When
/// one arrives the write path does not change — there is already a queue
/// holding deltas, keyed for idempotency.
@DataClassName('OutboxEntryRow')
class OutboxEntries extends Table {
  TextColumn get id => text()();
  TextColumn get idempotencyKey => text().unique()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operation => text()();
  TextColumn get payloadJson => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAt => integer()();
  TextColumn get lastError => text().nullable()();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Small key/value store for app preferences and engine bookkeeping
/// (last compliance alert, reminder cadence, and so on).
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {key};
}
