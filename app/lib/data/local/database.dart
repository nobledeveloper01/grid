import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables/tables.dart';

part 'database.g.dart';

/// Grid's local store, and the **source of truth** for the whole app.
///
/// Every read path in the application reads from here. No screen ever awaits
/// the network to render; when sync eventually exists it will write *into*
/// this database and the UI will observe the change, so the network stays
/// invisible to the presentation layer.
@DriftDatabase(
  tables: [
    Meters,
    Readings,
    Purchases,
    SupplyEvents,
    Appliances,
    BillingCycles,
    OutboxEntries,
    AppSettings,
  ],
)
class GridDatabase extends _$GridDatabase {
  GridDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'grid'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndices();
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Future<void> _createIndices() async {
    // The hot path for every engine: a meter's readings, newest first.
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_readings_meter_time '
      'ON readings (meter_id, read_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_supply_meter_time '
      'ON supply_events (meter_id, started_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_purchases_meter_time '
      'ON purchases (meter_id, purchased_at DESC)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_outbox_pending '
      'ON outbox_entries (state, next_attempt_at)',
    );
  }
}
