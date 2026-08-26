import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/reading.dart';
import 'package:grid/domain/entities/supply_event.dart';
import 'package:grid/domain/services/band_adherence_engine.dart';
import 'package:grid/domain/services/dispute_pack_engine.dart';
import 'package:grid/domain/services/escalation_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

final _rates = {
  TariffBand.a: Rate.fromNaira(225),
  TariffBand.b: Rate.fromNaira(160),
  TariffBand.c: Rate.fromNaira(90),
  TariffBand.d: Rate.fromNaira(66),
  TariffBand.e: Rate.fromNaira(55),
};

/// Readings every four days across [days], at a flat daily draw.
List<Reading> _readings(int days, {int flagAt = -1}) {
  final out = <Reading>[];
  var register = 1000.0;
  var i = 0;
  for (var d = days; d >= 0; d -= 4) {
    out.add(reading(
      id: 'r$i',
      value: i == flagAt ? register + 900 : register,
      at: now.subtract(Duration(days: d)),
      flags: i == flagAt ? ReadingFlag.anomalousHigh.bit : 0,
    ));
    register += 40;
    i++;
  }
  return out;
}

/// Fully-observed days at [hoursOn] hours of supply each.
List<SupplyEvent> _supply(int days, {int hoursOn = 8}) {
  final out = <SupplyEvent>[];
  for (var d = days; d >= 1; d--) {
    final start =
        DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
    out.add(supply(
      id: 'on-$d',
      state: SupplyState.available,
      from: start,
      to: start.add(Duration(hours: hoursOn)),
    ));
    out.add(supply(
      id: 'off-$d',
      state: SupplyState.unavailable,
      from: start.add(Duration(hours: hoursOn)),
      to: start.add(const Duration(hours: 24)),
    ));
  }
  return out;
}

void main() {
  const engine = DisputePackEngine();
  final periodEnd = now;

  group('eligibility', () {
    test('refuses a period shorter than a fortnight', () {
      final r = engine.check(
        kind: PackKind.consumptionRecord,
        meter: meter(),
        readings: _readings(30),
        supply: _supply(30),
        periodStart: now.subtract(const Duration(days: 10)),
        periodEnd: periodEnd,
        now: now,
      );
      expect(r, isA<PackBlocked>());
      expect((r as PackBlocked).reason, PackBlock.tooShort);
      expect(r.detail, contains('14 days'));
    });

    test('refuses when fewer than two clean readings fall inside', () {
      final r = engine.check(
        kind: PackKind.consumptionRecord,
        meter: meter(),
        readings: [reading(id: 'only', value: 1000, at: now)],
        supply: _supply(30),
        periodStart: now.subtract(const Duration(days: 30)),
        periodEnd: periodEnd,
        now: now,
      );
      expect((r as PackBlocked).reason, PackBlock.tooFewReadings);
    });

    test('an outage pack does not need readings', () {
      final r = engine.check(
        kind: PackKind.prolongedOutage,
        meter: meter(),
        readings: const [],
        supply: _supply(30),
        periodStart: now.subtract(const Duration(days: 30)),
        periodEnd: periodEnd,
        now: now,
      );
      expect(r, isA<PackReady>());
    });

    test('a band pack needs a band', () {
      final r = engine.check(
        kind: PackKind.bandShortfall,
        meter: meter(band: null),
        readings: _readings(30),
        supply: _supply(30),
        periodStart: now.subtract(const Duration(days: 30)),
        periodEnd: periodEnd,
        now: now,
      );
      expect((r as PackBlocked).reason, PackBlock.noBand);
    });

    test('a band pack refuses thin supply coverage', () {
      // Ten observed days inside a thirty-day period.
      final r = engine.check(
        kind: PackKind.bandShortfall,
        meter: meter(),
        readings: _readings(30),
        supply: _supply(10),
        periodStart: now.subtract(const Duration(days: 30)),
        periodEnd: periodEnd,
        now: now,
      );
      expect((r as PackBlocked).reason, PackBlock.supplyCoverageTooLow);
      expect(r.detail, contains('%'));
    });

    test('a well-covered band pack is ready', () {
      final r = engine.check(
        kind: PackKind.bandShortfall,
        meter: meter(),
        readings: _readings(30),
        supply: _supply(30),
        periodStart: now.subtract(const Duration(days: 30)),
        periodEnd: periodEnd,
        now: now,
      );
      expect(r, isA<PackReady>());
    });
  });

  group('assembly', () {
    DisputePack buildPack({
      PackKind kind = PackKind.bandShortfall,
      int flagAt = -1,
    }) =>
        engine.build(
          kind: kind,
          meter: meter(),
          readings: _readings(30, flagAt: flagAt),
          purchases: const [],
          supply: _supply(30),
          periodStart: now.subtract(const Duration(days: 30)),
          periodEnd: periodEnd,
          now: now,
          billedRate: _rates[TariffBand.a],
          rateForBand: (b) => _rates[b],
        );

    test('a flagged reading is listed and excluded, never silently dropped',
        () {
      final pack = buildPack(flagAt: 3);
      expect(pack.excluded, hasLength(1));
      expect(pack.evidence.length,
          pack.included.length + pack.excluded.length);
      expect(pack.excluded.single.exclusionReason, isNotNull);
      expect(pack.excluded.single.exclusionReason, contains('above the usual'),
          reason: 'the reason is printed, so it has to be plain language');
    });

    test('every reading in the period appears somewhere in the pack', () {
      final readings = _readings(30, flagAt: 2);
      final pack = buildPack(flagAt: 2);
      final inPeriod = readings
          .where((r) => !r.readAt.isBefore(now.subtract(const Duration(days: 30))))
          .length;
      expect(pack.evidence, hasLength(inPeriod));
    });

    test('states its own coverage rather than implying completeness', () {
      final pack = buildPack();
      expect(pack.supplyCoverage, greaterThan(0));
      expect(pack.supplyCoverage, lessThanOrEqualTo(1));
      expect(pack.readingCoverage, greaterThan(0));
    });

    test('carries the band valuation on a shortfall pack', () {
      final pack = buildPack();
      expect(pack.adherence, isA<AdherenceShortfall>());
      final short = pack.adherence! as AdherenceShortfall;
      expect(short.measuredHours, closeTo(8, 0.2));
      expect(short.deliveredBand, TariffBand.d);
    });

    test('carries no band valuation on a consumption record', () {
      expect(buildPack(kind: PackKind.consumptionRecord).adherence, isNull);
    });

    test('collects a photo hash for every reading that has one', () {
      final pack = engine.build(
        kind: PackKind.consumptionRecord,
        meter: meter(),
        readings: [
          reading(id: 'p1', value: 1000, at: now.subtract(const Duration(days: 20))),
          Reading(
            id: 'p2',
            meterId: 'm1',
            value: Kwh.fromDouble(1200),
            readAt: now.subtract(const Duration(days: 4)),
            recordedAt: now.subtract(const Duration(days: 4)),
            source: ReadingSource.ocr,
            photoPath: '/x.jpg',
            photoSha256: 'abc123',
          ),
        ],
        purchases: const [],
        supply: const [],
        periodStart: now.subtract(const Duration(days: 30)),
        periodEnd: periodEnd,
        now: now,
      );
      expect(pack.photoHashes, {'p2': 'abc123'});
    });

    test('the consumption total is the period, not the whole history', () {
      final pack = engine.build(
        kind: PackKind.consumptionRecord,
        meter: meter(),
        readings: _readings(120),
        purchases: const [],
        supply: const [],
        periodStart: now.subtract(const Duration(days: 30)),
        periodEnd: periodEnd,
        now: now,
      );
      // 30 days at 10 kWh a day, not 120.
      expect(pack.consumption.total.value, closeTo(300, 25));
    });
  });

  group('escalation', () {
    const ladder = EscalationEngine();

    test('nothing submitted means nothing to escalate', () {
      final s = ladder.evaluate(
        step: EscalationStep.businessUnit,
        status: CaseStatus.open,
        submittedAt: null,
        now: now,
      );
      expect(s.canEscalate, isFalse);
      expect(s.daysElapsed, isNull);
    });

    test('counts down the wait and then opens the next step', () {
      final waiting = ladder.evaluate(
        step: EscalationStep.businessUnit,
        status: CaseStatus.awaitingResponse,
        submittedAt: now.subtract(const Duration(days: 5)),
        now: now,
      );
      expect(waiting.daysElapsed, 5);
      expect(waiting.daysRemaining, 10);
      expect(waiting.canEscalate, isFalse);

      final ready = ladder.evaluate(
        step: EscalationStep.businessUnit,
        status: CaseStatus.awaitingResponse,
        submittedAt: now.subtract(const Duration(days: 20)),
        now: now,
      );
      expect(ready.daysRemaining, 0);
      expect(ready.canEscalate, isTrue);
    });

    test('a resolved case stops counting', () {
      final s = ladder.evaluate(
        step: EscalationStep.forumOffice,
        status: CaseStatus.resolved,
        submittedAt: now.subtract(const Duration(days: 90)),
        now: now,
      );
      expect(s.canEscalate, isFalse);
      expect(s.daysElapsed, isNull);
    });

    test('the last step has nowhere to escalate to', () {
      final s = ladder.evaluate(
        step: EscalationStep.commission,
        status: CaseStatus.awaitingResponse,
        submittedAt: now.subtract(const Duration(days: 200)),
        now: now,
      );
      expect(s.canEscalate, isFalse);
      expect(s.daysRemaining, isNull);
      expect(s.daysElapsed, 200);
      expect(EscalationStep.commission.next, isNull);
    });

    test('the ladder is ordered and every step but the last has a wait', () {
      for (final step in EscalationStep.values) {
        if (step.next == null) {
          expect(step.waitDays, isNull);
        } else {
          expect(step.waitDays, isNotNull);
          expect(step.waitDays, greaterThan(0));
        }
      }
    });
  });

  group('supply log detail', () {
    test('short periods print every day', () {
      expect(DisputePackEngine.detailFor(30), SupplyDetail.daily);
      expect(DisputePackEngine.detailFor(45), SupplyDetail.daily);
    });

    test('a couple of months rolls up to weeks, a year to months', () {
      expect(DisputePackEngine.detailFor(46), SupplyDetail.weekly);
      expect(DisputePackEngine.detailFor(200), SupplyDetail.weekly);
      expect(DisputePackEngine.detailFor(365), SupplyDetail.monthly);
    });

    test('a rolled-up mean excludes unobserved days rather than zeroing them',
        () {
      // Three days: eight hours, twelve hours, and one nobody observed.
      // Counting the third as zero would manufacture an outage — the one
      // direction this must never round in, and the one that would flatter
      // the user's own case.
      final days = [
        PackSupplyDay(
          date: DateTime(2026, 8, 1), hoursOn: 8, coverage: 1, isUsable: true),
        PackSupplyDay(
          date: DateTime(2026, 8, 2), hoursOn: 12, coverage: 1, isUsable: true),
        PackSupplyDay(
          date: DateTime(2026, 8, 3), hoursOn: 0, coverage: 0.1,
          isUsable: false),
      ];
      final buckets = engine.bucket(days, SupplyDetail.monthly);
      expect(buckets, hasLength(1));
      expect(buckets.single.meanHoursPerDay, 10);
      expect(buckets.single.usableDays, 2);
      expect(buckets.single.totalDays, 3);
    });

    test('a bucket with nothing observed reports itself as not counted', () {
      final buckets = engine.bucket(
        [
          PackSupplyDay(
            date: DateTime(2026, 8, 1), hoursOn: 0, coverage: 0,
            isUsable: false),
        ],
        SupplyDetail.monthly,
      );
      expect(buckets.single.isUsable, isFalse);
    });

    test('the worst days are the least-supplied observed ones, in order', () {
      final days = [
        PackSupplyDay(
          date: DateTime(2026, 8, 1), hoursOn: 9, coverage: 1, isUsable: true),
        PackSupplyDay(
          date: DateTime(2026, 8, 2), hoursOn: 2, coverage: 1, isUsable: true),
        PackSupplyDay(
          date: DateTime(2026, 8, 3), hoursOn: 0, coverage: 0.2,
          isUsable: false),
        PackSupplyDay(
          date: DateTime(2026, 8, 4), hoursOn: 5, coverage: 1, isUsable: true),
      ];
      final worst = engine.worstOf(days);
      expect(worst.map((d) => d.hoursOn), [2, 5, 9]);
      expect(worst.any((d) => !d.isUsable), isFalse,
          reason: 'an unobserved day is not a bad day, it is an unknown one');
    });

    test('a year-long pack rolls up and names its worst days', () {
      final supplyEvents = <SupplyEvent>[];
      for (var d = 365; d >= 1; d--) {
        final start =
            DateTime(now.year, now.month, now.day).subtract(Duration(days: d));
        final hours = d == 100 ? 1 : 9;
        supplyEvents.add(supply(
          id: 'on-$d',
          state: SupplyState.available,
          from: start,
          to: start.add(Duration(hours: hours)),
        ));
        supplyEvents.add(supply(
          id: 'off-$d',
          state: SupplyState.unavailable,
          from: start.add(Duration(hours: hours)),
          to: start.add(const Duration(hours: 24)),
        ));
      }

      final pack = engine.build(
        kind: PackKind.prolongedOutage,
        meter: meter(),
        readings: _readings(365),
        purchases: const [],
        supply: supplyEvents,
        periodStart: now.subtract(const Duration(days: 365)),
        periodEnd: periodEnd,
        now: now,
      );

      expect(pack.supplyDetail, SupplyDetail.monthly);
      expect(pack.supplyBuckets.length, lessThan(15),
          reason: '366 daily rows overran the PDF page limit outright');
      expect(pack.worstDays, isNotEmpty);
      expect(pack.worstDays.first.hoursOn, closeTo(1, 0.01));
    });
  });

  group('exclusion reasons', () {
    // These strings are printed in a document somebody reads aloud while
    // defending their own record, so every branch is exercised and every
    // one has to be a sentence rather than an enum name.
    for (final flag in ReadingFlag.values) {
      test('${flag.name} produces a plain-language reason', () {
        final pack = engine.build(
          kind: PackKind.consumptionRecord,
          meter: meter(),
          readings: [
            reading(
                id: 'clean1',
                value: 1000,
                at: now.subtract(const Duration(days: 25))),
            reading(
              id: 'flagged',
              value: 1100,
              at: now.subtract(const Duration(days: 15)),
              flags: flag.bit,
            ),
            reading(
                id: 'clean2',
                value: 1200,
                at: now.subtract(const Duration(days: 5))),
          ],
          purchases: const [],
          supply: const [],
          periodStart: now.subtract(const Duration(days: 30)),
          periodEnd: periodEnd,
          now: now,
        );

        final item =
            pack.evidence.where((e) => e.reading.id == 'flagged').single;

        // The gate: a flagged reading is excluded, or it is shown flagged.
        // There is no third state where it is quietly included as clean.
        expect(item.isFlagged, isTrue);
        expect(item.note, isNotNull,
            reason: 'a flagged reading always carries a note either way');
        expect(item.isIncluded, flag.excludesFromBaseline ? isFalse : isTrue);
        if (flag.excludesFromBaseline) {
          expect(item.exclusionReason, isNotNull);
          expect(item.flagNote, isNull);
        } else {
          expect(item.flagNote, isNotNull);
          expect(item.exclusionReason, isNull);
        }

        final reason = item.note!;
        expect(reason, isNotEmpty);
        expect(reason.endsWith('.'), isTrue,
            reason: 'it is printed as a sentence');
        expect(reason.toLowerCase(), isNot(contains(flag.name.toLowerCase())),
            reason: 'an enum name is not an explanation');
      });
    }
  });
}
