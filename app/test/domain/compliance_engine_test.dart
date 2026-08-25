import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/supply_event.dart';
import 'package:grid/domain/services/compliance_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';

import '_fixtures.dart';

void main() {
  const engine = ComplianceEngine();

  /// [hoursOn] of supply on each of the last [days] days, from midnight.
  List<SupplyEvent> run({
    required int hoursOn,
    required int days,
    required DateTime endingAt,
    SupplySource source = SupplySource.manual,
  }) {
    final events = <SupplyEvent>[];
    for (var i = 1; i <= days; i++) {
      final day = DateTime(endingAt.year, endingAt.month, endingAt.day)
          .subtract(Duration(days: i));
      events.add(supply(
        id: 'on$i',
        state: SupplyState.available,
        from: day,
        to: day.add(Duration(hours: hoursOn)),
        source: source,
      ));
      events.add(supply(
        id: 'off$i',
        state: SupplyState.unavailable,
        from: day.add(Duration(hours: hoursOn)),
        to: day.add(const Duration(hours: 24)),
        source: source,
      ));
    }
    return events;
  }

  group('summarise', () {
    test('computes daily hours and full coverage from complete events', () {
      final s = engine.summarise(
        events: run(hoursOn: 11, days: 10, endingAt: now),
        windowStart: now.subtract(const Duration(days: 10)),
        windowEnd: now.subtract(const Duration(days: 1)),
        now: now,
      );
      expect(s.rollingAverageHours, closeTo(11, 0.1));
      expect(s.coverage, closeTo(1.0, 0.05));
      expect(s.hasEnoughData, isTrue);
    });

    test('counts unobserved time as unknown rather than guessing', () {
      // Only 6 hours of the day were ever observed.
      final day = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1));
      final s = engine.summarise(
        events: [
          supply(
            id: 'a',
            state: SupplyState.available,
            from: day,
            to: day.add(const Duration(hours: 6)),
          ),
        ],
        windowStart: day,
        windowEnd: day.add(const Duration(hours: 23)),
        now: now,
      );
      final d = s.days.first;
      expect(d.availableMinutes, 6 * 60);
      expect(d.unknownMinutes, 18 * 60);
      expect(d.coverage, closeTo(0.25, 0.01));
      expect(d.isUsable, isFalse);
    });

    test('excludes low-coverage days from the average', () {
      final events = run(hoursOn: 20, days: 8, endingAt: now);
      // A ninth day observed for only one hour, which would drag the
      // average down badly if it were counted.
      final sparseDay = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 9));
      events.add(supply(
        id: 'sparse',
        state: SupplyState.available,
        from: sparseDay,
        to: sparseDay.add(const Duration(hours: 1)),
      ));

      final s = engine.summarise(
        events: events,
        windowStart: now.subtract(const Duration(days: 9)),
        windowEnd: now.subtract(const Duration(days: 1)),
        now: now,
      );
      expect(s.rollingAverageHours, closeTo(20, 0.5));
    });

    test('ignores superseded events', () {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(const Duration(days: 1));
      final s = engine.summarise(
        events: [
          SupplyEvent(
            id: 'inferred',
            meterId: 'm1',
            state: SupplyState.available,
            startedAt: day,
            endedAt: day.add(const Duration(hours: 24)),
            source: SupplySource.inferredCharging,
            platformCapability: PlatformCapability.periodic,
            supersededById: 'manual',
          ),
          supply(
            id: 'manual',
            state: SupplyState.available,
            from: day,
            to: day.add(const Duration(hours: 5)),
          ),
        ],
        windowStart: day,
        windowEnd: day.add(const Duration(hours: 23)),
        now: now,
      );
      expect(s.days.first.availableMinutes, 5 * 60);
    });
  });

  group('evaluate', () {
    test('detects a Band A breach with good coverage', () {
      final r = engine.evaluate(
        band: TariffBand.a,
        events: run(hoursOn: 11, days: 30, endingAt: now),
        now: now,
      );
      expect(r.isBreach, isTrue);
      expect(r.canRaiseAlert, isTrue);
      expect(r.shortfallHours, closeTo(9, 0.5));
      expect(r.shortfallPercent, closeTo(0.45, 0.05));
    });

    test('does not call a marginal shortfall a breach', () {
      // 19 hours against a 20-hour commitment is a 5% shortfall — inside
      // the noise threshold.
      final r = engine.evaluate(
        band: TariffBand.a,
        events: run(hoursOn: 19, days: 30, endingAt: now),
        now: now,
      );
      expect(r.isBreach, isFalse);
    });

    test('will not raise an alert on thin coverage', () {
      // Two days of data in a 30-day window: a real shortfall, but nowhere
      // near enough evidence to act on.
      final r = engine.evaluate(
        band: TariffBand.a,
        events: run(hoursOn: 4, days: 2, endingAt: now),
        now: now,
      );
      expect(r.canRaiseAlert, isFalse);
    });

    test('a compliant supply is not a breach', () {
      final r = engine.evaluate(
        band: TariffBand.c,
        events: run(hoursOn: 14, days: 30, endingAt: now),
        now: now,
      );
      expect(r.isBreach, isFalse);
      expect(r.shortfallHours, lessThan(0));
    });
  });

  group('alert hysteresis', () {
    test('allows a first alert', () {
      final r = engine.evaluate(
        band: TariffBand.a,
        events: run(hoursOn: 10, days: 30, endingAt: now),
        now: now,
      );
      expect(engine.shouldAlert(result: r, now: now), isTrue);
    });

    test('suppresses a repeat inside the cooldown', () {
      final r = engine.evaluate(
        band: TariffBand.a,
        events: run(hoursOn: 10, days: 30, endingAt: now),
        now: now,
      );
      expect(
        engine.shouldAlert(
          result: r,
          now: now,
          lastAlertedAt: now.subtract(const Duration(days: 5)),
        ),
        isFalse,
      );
    });

    test('allows again after the cooldown', () {
      final r = engine.evaluate(
        band: TariffBand.a,
        events: run(hoursOn: 10, days: 30, endingAt: now),
        now: now,
      );
      expect(
        engine.shouldAlert(
          result: r,
          now: now,
          lastAlertedAt: now.subtract(const Duration(days: 15)),
        ),
        isTrue,
      );
    });
  });
}
