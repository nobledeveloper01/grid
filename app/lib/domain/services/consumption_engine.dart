import '../entities/meter.dart';
import '../entities/reading.dart';
import '../value_objects/enums.dart';
import '../value_objects/units.dart';

/// Consumption over one interval between two readings.
class ConsumptionInterval {
  const ConsumptionInterval({
    required this.from,
    required this.to,
    required this.consumed,
    required this.days,
    this.isEstimated = false,
  });

  final DateTime from;
  final DateTime to;
  final Kwh consumed;
  final double days;

  /// True where the interval spans a meter replacement or rollover and the
  /// figure had to be inferred rather than measured.
  final bool isEstimated;

  double get dailyRate => days <= 0 ? 0 : consumed.value / days;
}

/// One day's consumption, interpolated across the reading interval it falls
/// in. Interpolated days are marked so the UI can render them distinctly —
/// mistaking an estimate for a measurement is the failure mode this product
/// most needs to prevent.
class DailyConsumption {
  const DailyConsumption({
    required this.date,
    required this.consumed,
    required this.isInterpolated,
  });

  final DateTime date;
  final Kwh consumed;
  final bool isInterpolated;
}

class ConsumptionSeries {
  const ConsumptionSeries({
    required this.intervals,
    required this.daily,
    required this.total,
    required this.excludedReadingCount,
    required this.coverage,
  });

  final List<ConsumptionInterval> intervals;
  final List<DailyConsumption> daily;
  final Kwh total;

  /// How many readings were excluded as flagged. Reported alongside every
  /// result rather than hidden.
  final int excludedReadingCount;

  /// Proportion of the requested window actually covered by readings, 0–1.
  final double coverage;

  bool get hasData => intervals.isNotEmpty;

  /// Energy consumed strictly between [from] and [to].
  ///
  /// [total] is the whole series, which is not the same thing — and reaching
  /// for it when a window was meant is a mistake that produces a figure three
  /// times too large without anything looking wrong. That happened once: a
  /// band-shortfall valuation multiplied a 30-day rate difference by ninety
  /// days of energy, and the resulting naira figure was confidently absurd.
  ///
  /// Sums the daily allocation, which is already apportioned by overlap, so
  /// an interval straddling the window boundary contributes only its share.
  /// The trade is that days derived by interpolation are included: a window
  /// narrower than the reading cadence is partly modelled, and a caller that
  /// makes a claim on this figure should say so.
  Kwh totalIn(DateTime from, DateTime to) {
    var sum = Kwh.zero;
    for (final d in daily) {
      if (d.date.isBefore(from)) continue;
      if (!d.date.isBefore(to)) continue;
      sum += d.consumed;
    }
    return sum;
  }

  /// Whether any day inside the window came from interpolation rather than
  /// from a reading interval that lands on it.
  bool isInterpolatedIn(DateTime from, DateTime to) => daily.any((d) =>
      !d.date.isBefore(from) && d.date.isBefore(to) && d.isInterpolated);

  /// Mean daily consumption over the covered period.
  ///
  /// Divides by the days actually spanned by the intervals, not by the
  /// number of day-buckets. Two half-days at the edges of a run are one
  /// day of consumption, not two.
  double get dailyMean {
    if (intervals.isEmpty) return 0;
    final days = intervals.fold<double>(0, (a, i) => a + i.days);
    if (days <= 0) return 0;
    return total.value / days;
  }
}

/// Derives consumption from readings.
///
/// Handles the prepaid/postpaid direction split, purchases inside an
/// interval, meter rollover and replacement, exclusion of flagged readings,
/// and daily interpolation — and reports coverage alongside every result.
class ConsumptionEngine {
  const ConsumptionEngine();

  /// Builds the consumption series for a meter.
  ///
  /// [readings] need not be sorted. Flagged and superseded readings are
  /// excluded from computation but counted in [ConsumptionSeries.excludedReadingCount].
  ConsumptionSeries series({
    required Meter meter,
    required List<Reading> readings,
    List<Purchase> purchases = const [],
    DateTime? windowStart,
    DateTime? windowEnd,
  }) {
    final all = readings.where((r) => !r.isSuperseded).toList();
    final clean = all.where((r) => r.isClean).toList()
      ..sort((a, b) => a.readAt.compareTo(b.readAt));
    final excluded = all.length - clean.length;

    if (clean.length < 2) {
      return ConsumptionSeries(
        intervals: const [],
        daily: const [],
        total: Kwh.zero,
        excludedReadingCount: excluded,
        coverage: 0,
      );
    }

    final intervals = <ConsumptionInterval>[];

    for (var i = 1; i < clean.length; i++) {
      final prev = clean[i - 1];
      final curr = clean[i];
      final days = curr.readAt.difference(prev.readAt).inMinutes / (60 * 24);
      if (days <= 0) continue;

      final purchasedInInterval = purchases
          .where((p) =>
              p.meterId == meter.id &&
              p.purchasedAt.isAfter(prev.readAt) &&
              !p.purchasedAt.isAfter(curr.readAt))
          .fold<Kwh>(Kwh.zero, (acc, p) => acc + (p.units ?? Kwh.zero));

      final consumed = switch (meter.direction) {
        // Cumulative meter: the register advances by what you used.
        MeterDirection.incrementing => curr.value - prev.value,
        // Prepaid meter: the balance falls by what you used, and rises by
        // whatever you loaded in between. Ignoring purchases here is the
        // classic way to compute a negative consumption.
        MeterDirection.decrementing =>
          (prev.value + purchasedInInterval) - curr.value,
        MeterDirection.none => Kwh.zero,
      };

      // A negative figure at this point means an unrecorded purchase or a
      // meter change. Clamp rather than propagate a nonsensical number, and
      // mark it estimated so it is never presented as measured.
      final safe = consumed.isNegative ? Kwh.zero : consumed;

      intervals.add(ConsumptionInterval(
        from: prev.readAt,
        to: curr.readAt,
        consumed: safe,
        days: days,
        isEstimated: consumed.isNegative,
      ));
    }

    final daily = _interpolateDaily(intervals);
    final total = intervals.fold<Kwh>(Kwh.zero, (a, i) => a + i.consumed);

    final coverage = _coverage(
      intervals: intervals,
      windowStart: windowStart ?? clean.first.readAt,
      windowEnd: windowEnd ?? clean.last.readAt,
    );

    return ConsumptionSeries(
      intervals: intervals,
      daily: daily,
      total: total,
      excludedReadingCount: excluded,
      coverage: coverage,
    );
  }

  /// Rolling mean daily consumption over the last [days] days of readings.
  /// Returns null where there is not enough data to be meaningful — a
  /// nullable result the caller must handle, rather than a misleading zero.
  double? rollingDailyMean({
    required Meter meter,
    required List<Reading> readings,
    List<Purchase> purchases = const [],
    required DateTime now,
    int days = 14,
  }) {
    final from = now.subtract(Duration(days: days));
    final windowed =
        readings.where((r) => !r.readAt.isBefore(from)).toList();
    if (windowed.length < 2) return null;

    final s = series(
      meter: meter,
      readings: windowed,
      purchases: purchases,
      windowStart: from,
      windowEnd: now,
    );
    if (!s.hasData) return null;

    final totalDays = s.intervals.fold<double>(0, (a, i) => a + i.days);
    if (totalDays <= 0) return null;
    return s.total.value / totalDays;
  }

  /// Apportions each interval's consumption across the calendar days it
  /// touches, in proportion to how much of each day the interval actually
  /// covers.
  ///
  /// Energy is conserved: the sum of the daily figures equals the sum of the
  /// interval figures, to within integer rounding. Allocating a full day's
  /// worth to every day an interval merely touches would inflate the total —
  /// a reading taken at noon each day touches two calendar days.
  ///
  /// A day is reported as measured only when a single interval covers it
  /// end to end, which in practice means the readings fell on midnight
  /// boundaries. Everything else is interpolated, and says so.
  List<DailyConsumption> _interpolateDaily(
    List<ConsumptionInterval> intervals,
  ) {
    const dayMinutes = 24 * 60;
    final byDay = <DateTime, int>{};
    final coveredMinutes = <DateTime, int>{};
    final contributingIntervals = <DateTime, int>{};
    final measuredExactly = <DateTime, bool>{};

    for (final interval in intervals) {
      final totalMinutes = interval.to.difference(interval.from).inMinutes;
      if (totalMinutes <= 0) continue;

      var cursor = DateTime(
        interval.from.year,
        interval.from.month,
        interval.from.day,
      );
      final last = DateTime(
        interval.to.year,
        interval.to.month,
        interval.to.day,
      );

      while (!cursor.isAfter(last)) {
        final dayEnd = cursor.add(const Duration(days: 1));
        final from =
            interval.from.isAfter(cursor) ? interval.from : cursor;
        final to = interval.to.isBefore(dayEnd) ? interval.to : dayEnd;
        final overlap = to.isAfter(from) ? to.difference(from).inMinutes : 0;

        if (overlap > 0) {
          final share = (interval.consumed.milli * overlap / totalMinutes)
              .round();
          byDay.update(cursor, (v) => v + share, ifAbsent: () => share);
          coveredMinutes.update(
            cursor,
            (v) => v + overlap,
            ifAbsent: () => overlap,
          );
          contributingIntervals.update(
            cursor,
            (v) => v + 1,
            ifAbsent: () => 1,
          );
          // Measured only if this one interval *is* this day. A day sitting
          // inside a six-day interval had its figure spread across it, not
          // observed.
          measuredExactly[cursor] =
              (measuredExactly[cursor] ?? true) && totalMinutes == dayMinutes;
        }

        cursor = dayEnd;
      }
    }

    final days = byDay.keys.toList()..sort();
    return [
      for (final d in days)
        DailyConsumption(
          date: d,
          consumed: Kwh.fromMilli(byDay[d]!),
          isInterpolated: !(contributingIntervals[d] == 1 &&
              coveredMinutes[d] == dayMinutes &&
              (measuredExactly[d] ?? false)),
        ),
    ];
  }

  double _coverage({
    required List<ConsumptionInterval> intervals,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final windowMinutes = windowEnd.difference(windowStart).inMinutes;
    if (windowMinutes <= 0) return 0;

    var covered = 0;
    for (final i in intervals) {
      final from = i.from.isAfter(windowStart) ? i.from : windowStart;
      final to = i.to.isBefore(windowEnd) ? i.to : windowEnd;
      if (to.isAfter(from)) covered += to.difference(from).inMinutes;
    }
    final ratio = covered / windowMinutes;
    return ratio > 1 ? 1 : ratio;
  }
}
