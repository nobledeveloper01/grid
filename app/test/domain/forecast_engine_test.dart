import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/reading.dart';
import 'package:grid/domain/services/forecast_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  const engine = ForecastEngine();

  /// A prepaid balance falling by [perDay] kWh for [days] days, ending at
  /// [endingAt] with [endValue] remaining.
  List<Reading> falling({
    required double endValue,
    required double perDay,
    required int days,
    required DateTime endingAt,
  }) =>
      [
        for (var i = 0; i < days; i++)
          reading(
            id: 'r$i',
            value: endValue + perDay * i,
            at: endingAt.subtract(Duration(days: i)),
          ),
      ];

  group('balance forecast preconditions', () {
    test('refuses on a postpaid meter', () {
      final f = engine.balance(
        meter: meter(),
        readings: const [],
        purchases: const [],
        now: now,
      );
      expect(f, isA<BalanceUnavailable>());
      expect(
        (f as BalanceUnavailable).reason,
        ForecastUnavailableReason.notPrepaid,
      );
    });

    test('reports how many more readings are needed', () {
      final f = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: [reading(id: 'a', value: 50, at: now)],
        purchases: const [],
        now: now,
      );
      expect(f, isA<BalanceUnavailable>());
      final u = f as BalanceUnavailable;
      expect(u.reason, ForecastUnavailableReason.notEnoughReadings);
      expect(u.readingsNeeded, 2);
    });

    test('refuses when there is no consumption to extrapolate from', () {
      final f = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: [
          reading(id: 'a', value: 50, at: now.subtract(const Duration(days: 2))),
          reading(id: 'b', value: 50, at: now.subtract(const Duration(days: 1))),
          reading(id: 'c', value: 50, at: now),
        ],
        purchases: const [],
        now: now,
      );
      expect(f, isA<BalanceUnavailable>());
      expect(
        (f as BalanceUnavailable).reason,
        ForecastUnavailableReason.noConsumptionYet,
      );
    });
  });

  group('balance forecast', () {
    test('projects a depletion date from the burn rate', () {
      final f = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: falling(endValue: 40, perDay: 10, days: 6, endingAt: now),
        purchases: const [],
        now: now,
      );
      expect(f, isA<BalanceKnown>());
      final k = f as BalanceKnown;
      expect(k.dailyMean, closeTo(10, 0.2));
      expect(k.daysRemaining, closeTo(4, 0.2));
      expect(k.depletesOn.isAfter(now), isTrue);
    });

    test('counts units loaded after the latest reading', () {
      final withoutLoad = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: falling(endValue: 20, perDay: 10, days: 6, endingAt: now),
        purchases: const [],
        now: now,
      ) as BalanceKnown;

      final withLoad = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: falling(endValue: 20, perDay: 10, days: 6, endingAt: now),
        purchases: [
          purchase(
            id: 'p',
            naira: 22500,
            units: 100,
            at: now.add(const Duration(minutes: 1)),
          ),
        ],
        now: now,
      ) as BalanceKnown;

      expect(withLoad.balance.value, greaterThan(withoutLoad.balance.value));
      expect(withLoad.daysRemaining, greaterThan(withoutLoad.daysRemaining));
    });

    test('flags urgency thresholds', () {
      // 25 kWh at ~10 kWh/day is 2.5 days: inside the 3-day warning window
      // but outside the 1-day urgent one.
      final warning = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: falling(endValue: 25, perDay: 10, days: 6, endingAt: now),
        purchases: const [],
        now: now,
      ) as BalanceKnown;
      expect(warning.needsWarning, isTrue);
      expect(warning.isUrgent, isFalse);

      final urgent = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: falling(endValue: 8, perDay: 10, days: 6, endingAt: now),
        purchases: const [],
        now: now,
      ) as BalanceKnown;
      expect(urgent.isUrgent, isTrue);
      expect(urgent.needsWarning, isTrue);
    });

    test('confidence band widens with less data', () {
      final thin = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: falling(endValue: 100, perDay: 10, days: 3, endingAt: now),
        purchases: const [],
        now: now,
      ) as BalanceKnown;
      final thick = engine.balance(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: falling(endValue: 100, perDay: 10, days: 15, endingAt: now),
        purchases: const [],
        now: now,
      ) as BalanceKnown;

      expect(thin.confidenceDays, greaterThan(thick.confidenceDays));
      expect(thin.isRough, isTrue);
      expect(thin.earliest.isBefore(thin.depletesOn), isTrue);
      expect(thin.latest.isAfter(thin.depletesOn), isTrue);
    });
  });

  group('cost projection', () {
    // A cycle that opened five days ago, so "so far" is a real quantity and
    // not an edge case.
    final cycleStart = now.subtract(const Duration(days: 5));

    test('refuses without enough readings', () {
      final c = engine.cost(
        meter: meter(),
        readings: const [],
        purchases: const [],
        rate: Rate.fromNaira(225),
        now: now,
        cycleStart: cycleStart,
        cycleEnd: now.add(const Duration(days: 20)),
      );
      expect(c, isA<CostUnavailable>());
    });

    test('projects to cycle end at the configured rate', () {
      final c = engine.cost(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 10, days: 15, endingAt: now),
        purchases: const [],
        rate: Rate.fromNaira(200),
        now: now,
        cycleStart: cycleStart,
        cycleEnd: now.add(const Duration(days: 10)),
      ) as CostProjected;

      // The projection covers the whole cycle: 5 days already used plus
      // 10 still to come, at 10 kWh a day and ₦200 — about ₦30,000.
      expect(c.consumedSoFar.value, closeTo(50, 2));
      expect(c.remainingKwh.value, closeTo(100, 2));
      expect(c.projectedKwh.value, closeTo(150, 4));
      expect(c.projectedCost.value, closeTo(30000, 800));
      expect(c.isRough, isFalse);
    });

    test('the uncertainty band brackets the remainder, not what was used',
        () {
      // Widening the whole figure would put a range around a measurement.
      final c = engine.cost(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 10, days: 15, endingAt: now),
        purchases: const [],
        rate: Rate.fromNaira(200),
        now: now,
        cycleStart: cycleStart,
        cycleEnd: now.add(const Duration(days: 10)),
      ) as CostProjected;

      expect(c.lowCost, greaterThan(c.costSoFar),
          reason: 'even the low end includes what has already happened');
      expect(c.lowCost < c.projectedCost, isTrue);
      expect(c.highCost > c.projectedCost, isTrue);

      // A 10% band on a 100 kWh remainder is ±20 kWh at ₦200 = ±₦4,000.
      final halfBand = (c.highCost.kobo - c.lowCost.kobo) / 2;
      expect(halfBand / 100, closeTo(2000, 250));
    });

    test('returns a wider range when data is thin', () {
      final thin = engine.cost(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 10, days: 4, endingAt: now),
        purchases: const [],
        rate: Rate.fromNaira(200),
        now: now,
        cycleStart: cycleStart,
        cycleEnd: now.add(const Duration(days: 10)),
      ) as CostProjected;

      final thick = engine.cost(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 10, days: 20, endingAt: now),
        purchases: const [],
        rate: Rate.fromNaira(200),
        now: now,
        cycleStart: cycleStart,
        cycleEnd: now.add(const Duration(days: 10)),
      ) as CostProjected;

      final thinSpread = thin.highCost.kobo - thin.lowCost.kobo;
      final thickSpread = thick.highCost.kobo - thick.lowCost.kobo;
      expect(thinSpread, greaterThan(thickSpread));
      expect(thin.isRough, isTrue);
    });

    test('never projects negative usage past the cycle end', () {
      final c = engine.cost(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 10, days: 15, endingAt: now),
        purchases: const [],
        rate: Rate.fromNaira(200),
        now: now,
        cycleStart: cycleStart,
        cycleEnd: now.subtract(const Duration(days: 3)),
      ) as CostProjected;
      // The remainder is clamped to nothing; what was already used stands.
      expect(c.remainingKwh, Kwh.zero);
      expect(c.projectedKwh, c.consumedSoFar);
    });
  });
}
