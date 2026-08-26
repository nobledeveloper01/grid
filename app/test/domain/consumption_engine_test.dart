import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/reading.dart';
import 'package:grid/domain/services/consumption_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  _windowedTotals();
  const engine = ConsumptionEngine();

  group('insufficient data', () {
    test('returns an empty series below two clean readings', () {
      final s = engine.series(
        meter: meter(),
        readings: [reading(id: 'r1', value: 100, at: now)],
      );
      expect(s.hasData, isFalse);
      expect(s.total, Kwh.zero);
      expect(s.coverage, 0);
    });
  });

  group('postpaid (incrementing)', () {
    test('derives consumption from the register advance', () {
      final s = engine.series(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 12, days: 5, endingAt: now),
      );
      expect(s.intervals.length, 4);
      expect(s.total.value, closeTo(48, 0.001));
      expect(s.intervals.first.dailyRate, closeTo(12, 0.001));
    });

    test('excludes flagged readings and reports how many', () {
      final readings = dailyRun(start: 1000, perDay: 10, days: 4, endingAt: now)
        ..add(reading(
          id: 'bad',
          value: 99999,
          at: now.subtract(const Duration(hours: 12)),
          flags: ReadingFlag.anomalousHigh.bit,
        ));
      final s = engine.series(meter: meter(), readings: readings);
      expect(s.excludedReadingCount, 1);
      expect(s.total.value, closeTo(30, 0.001));
    });

    test('excludes superseded readings', () {
      final readings = dailyRun(start: 1000, perDay: 10, days: 3, endingAt: now)
        ..add(reading(
          id: 'old',
          value: 5000,
          at: now.subtract(const Duration(hours: 6)),
          supersededById: 'r0',
        ));
      final s = engine.series(meter: meter(), readings: readings);
      expect(s.total.value, closeTo(20, 0.001));
    });
  });

  group('prepaid (decrementing)', () {
    test('derives consumption from the balance falling', () {
      final s = engine.series(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: [
          reading(id: 'a', value: 100, at: now.subtract(const Duration(days: 2))),
          reading(id: 'b', value: 80, at: now.subtract(const Duration(days: 1))),
          reading(id: 'c', value: 60, at: now),
        ],
      );
      expect(s.total.value, closeTo(40, 0.001));
    });

    test('accounts for units loaded mid-interval', () {
      // Balance goes 20 -> 90 because 100 units were loaded. Naively that
      // reads as negative consumption; correctly it is 30 kWh used.
      final s = engine.series(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: [
          reading(id: 'a', value: 20, at: now.subtract(const Duration(days: 1))),
          reading(id: 'b', value: 90, at: now),
        ],
        purchases: [
          purchase(
            id: 'p1',
            naira: 22500,
            units: 100,
            at: now.subtract(const Duration(hours: 12)),
          ),
        ],
      );
      expect(s.total.value, closeTo(30, 0.001));
      expect(s.intervals.single.isEstimated, isFalse);
    });

    test('clamps and marks estimated when a purchase went unrecorded', () {
      final s = engine.series(
        meter: meter(type: MeterType.prepaidKeypad),
        readings: [
          reading(id: 'a', value: 20, at: now.subtract(const Duration(days: 1))),
          reading(id: 'b', value: 90, at: now),
        ],
      );
      expect(s.total, Kwh.zero);
      expect(s.intervals.single.isEstimated, isTrue);
    });
  });

  group('daily interpolation', () {
    test('marks every day of a long interval as interpolated', () {
      // 60 kWh observed once, six days apart. No individual day was measured.
      final s = engine.series(
        meter: meter(),
        readings: [
          reading(id: 'a', value: 1000, at: now.subtract(const Duration(days: 6))),
          reading(id: 'b', value: 1060, at: now),
        ],
      );
      expect(s.daily.every((d) => d.isInterpolated), isTrue);
      expect(s.daily.length, 7);
    });

    test('marks a day as measured only when readings align to midnight', () {
      final midnight = DateTime(2026, 8, 20);
      final s = engine.series(
        meter: meter(),
        readings: [
          reading(id: 'a', value: 1000, at: midnight),
          reading(id: 'b', value: 1010, at: midnight.add(const Duration(days: 1))),
        ],
      );
      final measured = s.daily.where((d) => !d.isInterpolated).toList();
      expect(measured, hasLength(1));
      expect(measured.single.consumed.value, closeTo(10, 0.001));
    });

    test('readings taken mid-day produce only interpolated days', () {
      // A reading at noon each day means no calendar day is measured
      // end-to-end — each is a blend of two intervals.
      final s = engine.series(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 10, days: 3, endingAt: now),
      );
      expect(s.daily.every((d) => d.isInterpolated), isTrue);
    });

    test('conserves energy: daily figures sum to the interval total', () {
      final s = engine.series(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 12, days: 6, endingAt: now),
      );
      final dailySum =
          s.daily.fold<int>(0, (a, d) => a + d.consumed.milli);
      // Within a few milli-kWh of rounding across the buckets.
      expect(dailySum, closeTo(s.total.milli, 10));
    });
  });

  group('coverage', () {
    test('reports partial coverage of a wider window', () {
      final s = engine.series(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 10, days: 5, endingAt: now),
        windowStart: now.subtract(const Duration(days: 30)),
        windowEnd: now,
      );
      // 4 days of intervals inside a 30-day window.
      expect(s.coverage, closeTo(4 / 30, 0.02));
    });

    test('never exceeds 1', () {
      final s = engine.series(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 10, days: 10, endingAt: now),
        windowStart: now.subtract(const Duration(days: 2)),
        windowEnd: now,
      );
      expect(s.coverage, lessThanOrEqualTo(1.0));
    });
  });

  group('rollingDailyMean', () {
    test('returns null with too little history rather than a misleading zero', () {
      expect(
        engine.rollingDailyMean(
          meter: meter(),
          readings: [reading(id: 'a', value: 100, at: now)],
          now: now,
        ),
        isNull,
      );
    });

    test('computes the mean over the window', () {
      final mean = engine.rollingDailyMean(
        meter: meter(),
        readings: dailyRun(start: 1000, perDay: 15, days: 8, endingAt: now),
        now: now,
        days: 7,
      );
      expect(mean, isNotNull);
      expect(mean!, closeTo(15, 0.1));
    });

    test('ignores readings outside the window', () {
      final readings = [
        reading(id: 'ancient', value: 0, at: now.subtract(const Duration(days: 200))),
        ...dailyRun(start: 1000, perDay: 20, days: 5, endingAt: now),
      ];
      final mean = engine.rollingDailyMean(
        meter: meter(),
        readings: readings,
        now: now,
        days: 7,
      );
      expect(mean!, closeTo(20, 0.1));
    });
  });
}

void _windowedTotals() {
  group('totalIn', () {
    const engine = ConsumptionEngine();

    // Ten readings, four days apart, at a flat 10 kWh a day.
    ConsumptionSeries flatSeries() {
      final readings = <Reading>[];
      var register = 1000.0;
      for (var i = 0; i < 10; i++) {
        readings.add(reading(
          id: 'r$i',
          value: register,
          at: now.subtract(Duration(days: 36 - i * 4)),
        ));
        register += 40;
      }
      return engine.series(meter: meter(), readings: readings);
    }

    test('a windowed series reports the window, not the history', () {
      // The trap: series() took a window and applied it only to coverage, so
      // `total` silently described ninety days while the screen said thirty.
      final readings = <Reading>[];
      var register = 1000.0;
      for (var i = 0; i < 10; i++) {
        readings.add(reading(
          id: 'w\$i',
          value: register,
          at: now.subtract(Duration(days: 36 - i * 4)),
        ));
        register += 40;
      }

      final whole = engine.series(meter: meter(), readings: readings);
      final month = engine.series(
        meter: meter(),
        readings: readings,
        windowStart: now.subtract(const Duration(days: 10)),
        windowEnd: now,
      );

      expect(whole.total.value, closeTo(360, 0.5));
      expect(month.total.value, closeTo(100, 12),
          reason: 'ten days at roughly ten a day');
      expect(month.dailyMean, closeTo(10, 1.5));
    });

    test('an interval straddling the boundary contributes its share', () {
      // Two readings twenty days apart at 200 kWh. A window opening halfway
      // through must see about half of it — not all of it, and not none.
      final readings = [
        reading(id: 'a', value: 1000, at: now.subtract(const Duration(days: 20))),
        reading(id: 'b', value: 1200, at: now),
      ];
      final half = engine.series(
        meter: meter(),
        readings: readings,
        windowStart: now.subtract(const Duration(days: 10)),
        windowEnd: now,
      );
      expect(half.total.value, closeTo(100, 0.5));
    });

    test('windows the total instead of returning the whole series', () {
      final s = flatSeries();
      final all = s.total.value;
      final tenDays = s.totalIn(now.subtract(const Duration(days: 10)), now);

      expect(all, closeTo(360, 0.5), reason: '36 days at 10 kWh a day');
      expect(tenDays, isNot(closeTo(all, 1)));
      expect(tenDays.value, closeTo(100, 12),
          reason: 'ten days at roughly 10 kWh a day');
    });

    test('a window covering everything matches the series total', () {
      final s = flatSeries();
      final wide = s.totalIn(
        now.subtract(const Duration(days: 400)),
        now.add(const Duration(days: 1)),
      );
      expect(wide.milli, s.total.milli);
    });

    test('a window before any data is zero, not the whole total', () {
      final s = flatSeries();
      final before = s.totalIn(
        now.subtract(const Duration(days: 400)),
        now.subtract(const Duration(days: 200)),
      );
      expect(before, Kwh.zero);
    });

    test('reports whether the window leans on interpolation', () {
      final s = flatSeries();
      // Readings are four days apart, so any single day between two of them
      // is allocated rather than measured.
      expect(
        s.isInterpolatedIn(
          now.subtract(const Duration(days: 3)),
          now.subtract(const Duration(days: 2)),
        ),
        isTrue,
      );
    });
  });
}
