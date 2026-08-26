import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/budget_engine.dart';
import 'package:grid/domain/services/forecast_engine.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  const engine = BudgetEngine();
  final rate = Rate.fromNaira(225);

  Budget budget({double monthly = 30000, int payDay = 28}) => Budget(
        monthly: Naira.fromNaira(monthly),
        payDayOfMonth: payDay,
      );

  BalanceKnown balance(DateTime depletesOn, {double dailyMean = 8}) =>
      BalanceKnown(
        balance: Kwh.fromDouble(40),
        dailyMean: dailyMean,
        depletesOn: depletesOn,
        daysRemaining: depletesOn.difference(now).inHours / 24,
        confidenceDays: 1,
        readingCount: 8,
      );

  group('nextPayDate', () {
    test('is this month when the day has not passed', () {
      // Fixtures fix `now` at 25 August 2026.
      expect(budget(payDay: 28).nextPayDate(now), DateTime(2026, 8, 28));
    });

    test('rolls to next month once the day has gone', () {
      expect(budget(payDay: 20).nextPayDate(now), DateTime(2026, 9, 20));
    });

    test('is today when today is pay day', () {
      expect(budget(payDay: 25).nextPayDate(now), DateTime(2026, 8, 25));
    });

    test('clamps to the length of a short month', () {
      // A pay day of the 31st still has to land in February.
      final b = budget(payDay: 31);
      expect(b.nextPayDate(DateTime(2026, 2, 10)), DateTime(2026, 2, 28));
      expect(b.nextPayDate(DateTime(2028, 2, 10)), DateTime(2028, 2, 29),
          reason: '2028 is a leap year');
    });

    test('handles a December pay day rolling into January', () {
      expect(
        budget(payDay: 5).nextPayDate(DateTime(2026, 12, 20)),
        DateTime(2027, 1, 5),
      );
    });
  });

  group('prepaid', () {
    test('units lasting past pay day are on track', () {
      final outlook = engine.fromBalance(
        budget: budget(payDay: 28),
        forecast: balance(DateTime(2026, 9, 2)),
        rate: rate,
        spentThisCycle: Naira.fromNaira(12000),
        now: now,
      );
      expect(outlook, isA<BudgetOnTrack>());
    });

    test('units running out first report the gap, not the whole spend', () {
      // Depletes on the 24th, paid on the 28th: four days to bridge at
      // 8 kWh a day and 225/kWh — about 7,200, not the whole month.
      final outlook = engine.fromBalance(
        budget: budget(payDay: 28),
        forecast: balance(DateTime(2026, 8, 24, 12)),
        rate: rate,
        spentThisCycle: Naira.fromNaira(12000),
        now: now,
      ) as BudgetShort;

      expect(outlook.shortfall.value, closeTo(7200, 900));
      expect(outlook.gapDays(), 3);
      expect(outlook.runsOutOn, DateTime(2026, 8, 24, 12));
    });

    test('a gap is never reported as negative days', () {
      final outlook = engine.fromBalance(
        budget: budget(payDay: 28),
        forecast: balance(DateTime(2026, 8, 27, 23)),
        rate: rate,
        spentThisCycle: Naira.zero,
        now: now,
      ) as BudgetShort;
      expect(outlook.gapDays(), greaterThanOrEqualTo(0));
    });

    test('no forecast means no claim about the pay date', () {
      final outlook = engine.fromBalance(
        budget: budget(),
        forecast: const BalanceUnavailable(
            ForecastUnavailableReason.notEnoughReadings, 2),
        rate: rate,
        spentThisCycle: Naira.zero,
        now: now,
      );
      expect(outlook, isA<BudgetUnknown>());
      expect((outlook as BudgetUnknown).reason, isNotEmpty);
    });
  });

  group('postpaid', () {
    CostProjected projection(double cost) => CostProjected(
          consumedSoFar: Kwh.fromDouble(cost / 225 * 0.8),
          projectedKwh: Kwh.fromDouble(cost / 225),
          projectedCost: Naira.fromNaira(cost),
          lowCost: Naira.fromNaira(cost * 0.9),
          highCost: Naira.fromNaira(cost * 1.1),
          rate: rate,
          daysOfData: 20,
          dailyMean: 10,
          cycleEnd: DateTime(2026, 9, 1),
        );

    test('a projected bill inside the budget is on track', () {
      final outlook = engine.fromProjection(
        budget: budget(monthly: 30000),
        projection: projection(24000),
        now: now,
      ) as BudgetOnTrack;
      expect(outlook.headroom.value, closeTo(6000, 0.01));
    });

    test('a projected bill over the budget reports the difference', () {
      final outlook = engine.fromProjection(
        budget: budget(monthly: 30000),
        projection: projection(38500),
        now: now,
      ) as BudgetShort;
      expect(outlook.shortfall.value, closeTo(8500, 0.01));
      expect(outlook.runsOutOn, isNull,
          reason: 'a postpaid bill has no balance to run out');
      expect(outlook.gapDays(), isNull);
    });

    test('no projection means no claim', () {
      expect(
        engine.fromProjection(
          budget: budget(),
          projection: const CostUnavailable(
              ForecastUnavailableReason.notEnoughReadings, 2),
          now: now,
        ),
        isA<BudgetUnknown>(),
      );
    });
  });
}
