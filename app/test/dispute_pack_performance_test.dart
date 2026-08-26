import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/reading.dart';
import 'package:grid/domain/entities/supply_event.dart';
import 'package:grid/domain/services/dispute_pack_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';
import 'package:grid/features/dispute/data/pack_renderer.dart';

import 'domain/_fixtures.dart';

/// Phase 5's exit gate: a twelve-month pack generates in under three seconds,
/// entirely offline.
///
/// Three seconds is not an arbitrary round number. The pack is generated at a
/// counter, on a phone, with somebody waiting — a spinner past about three
/// seconds reads as a hang, and the user closes the app and loses their turn.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = DisputePackEngine();
  const renderer = PackRenderer();

  /// A full year: readings every four days, supply logged in four blocks a
  /// day, every day. Larger than a real household's record, deliberately.
  ({List<Reading> readings, List<SupplyEvent> supply}) yearOfData() {
    final readings = <Reading>[];
    var register = 20000.0;
    for (var d = 365; d >= 0; d -= 4) {
      readings.add(reading(
        id: 'r$d',
        value: register,
        at: now.subtract(Duration(days: d)),
        flags: d % 60 == 5 ? ReadingFlag.anomalousHigh.bit : 0,
      ));
      register += 42;
    }

    final supply = <SupplyEvent>[];
    for (var d = 365; d >= 1; d--) {
      final day =
          DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
      for (var block = 0; block < 4; block++) {
        supply.add(SupplyEvent(
          id: 's-$d-$block',
          meterId: 'm1',
          state: block.isEven
              ? SupplyState.available
              : SupplyState.unavailable,
          startedAt: day.add(Duration(hours: block * 6)),
          endedAt: day.add(Duration(hours: (block + 1) * 6)),
          source: SupplySource.inferredCharging,
          platformCapability: PlatformCapability.periodic,
        ));
      }
    }

    return (readings: readings, supply: supply);
  }

  test('a twelve-month pack assembles and renders in under three seconds',
      () async {
    final data = yearOfData();
    final start = now.subtract(const Duration(days: 365));

    final watch = Stopwatch()..start();

    final eligibility = engine.check(
      kind: PackKind.bandShortfall,
      meter: meter(),
      readings: data.readings,
      supply: data.supply,
      periodStart: start,
      periodEnd: now,
      now: now,
    );
    expect(eligibility, isA<PackReady>());

    final pack = engine.build(
      kind: PackKind.bandShortfall,
      meter: meter(),
      readings: data.readings,
      purchases: const [],
      supply: data.supply,
      periodStart: start,
      periodEnd: now,
      now: now,
      billedRate: Rate.fromNaira(225),
      rateForBand: (b) => Rate.fromKobo(b.committedHours * 1100),
    );

    final bytes = await renderer.render(pack);
    watch.stop();

    expect(bytes.length, greaterThan(10000),
        reason: 'a year of readings and supply is not a one-page document');
    expect(
      watch.elapsedMilliseconds,
      lessThan(3000),
      reason: 'phase 5 exit gate — took ${watch.elapsedMilliseconds} ms',
    );
    // Reported either way, so a run that is merely inside the gate but
    // creeping towards it is visible rather than silently passing.
    // ignore: avoid_print
    print('12-month pack: ${watch.elapsedMilliseconds} ms, '
        '${(bytes.length / 1024).round()} KB, '
        '${pack.evidence.length} readings, '
        '${pack.supplyDays.length} days');
  });

  test('the year pack still lists every excluded reading with a reason',
      () async {
    final data = yearOfData();
    final pack = engine.build(
      kind: PackKind.consumptionRecord,
      meter: meter(),
      readings: data.readings,
      purchases: const [],
      supply: data.supply,
      periodStart: now.subtract(const Duration(days: 365)),
      periodEnd: now,
      now: now,
    );

    expect(pack.excluded, isNotEmpty);
    for (final e in pack.excluded) {
      expect(e.exclusionReason, isNotNull);
      expect(e.exclusionReason, isNotEmpty);
    }
    expect(pack.evidence.length,
        pack.included.length + pack.excluded.length);
  });
}
