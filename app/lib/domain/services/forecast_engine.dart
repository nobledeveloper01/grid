import '../entities/meter.dart';
import '../entities/reading.dart';
import '../value_objects/units.dart';
import 'consumption_engine.dart';

/// Why a forecast could not be produced. A first-class result rather than a
/// null, so the UI cannot accidentally render a misleading figure.
enum ForecastUnavailableReason {
  notEnoughReadings,
  noBalanceKnown,
  noConsumptionYet,
  notPrepaid,
}

/// A prepaid depletion forecast.
sealed class BalanceForecast {
  const BalanceForecast();

  static const int warnAtDays = 3;
  static const int urgentAtDays = 1;
}

final class BalanceKnown extends BalanceForecast {
  const BalanceKnown({
    required this.balance,
    required this.dailyMean,
    required this.depletesOn,
    required this.daysRemaining,
    required this.confidenceDays,
    required this.readingCount,
  });

  final Kwh balance;
  final double dailyMean;
  final DateTime depletesOn;
  final double daysRemaining;

  /// Half-width of the confidence interval, in days. Widens with less data.
  final double confidenceDays;

  final int readingCount;

  DateTime get earliest =>
      depletesOn.subtract(Duration(hours: (confidenceDays * 24).round()));
  DateTime get latest =>
      depletesOn.add(Duration(hours: (confidenceDays * 24).round()));

  bool get isUrgent => daysRemaining <= BalanceForecast.urgentAtDays;
  bool get needsWarning => daysRemaining <= BalanceForecast.warnAtDays;

  /// True where there is too little history to state a single date with a
  /// straight face.
  bool get isRough => readingCount < 4 || confidenceDays > 2;
}

final class BalanceUnavailable extends BalanceForecast {
  const BalanceUnavailable(this.reason, this.readingsNeeded);
  final ForecastUnavailableReason reason;

  /// How many more readings would make a forecast possible. Drives the
  /// guidance copy — "log two more readings and we can tell you...".
  final int readingsNeeded;
}

/// A postpaid cost projection to the end of the billing cycle.
sealed class CostProjection {
  const CostProjection();
}

final class CostProjected extends CostProjection {
  const CostProjected({
    required this.consumedSoFar,
    required this.projectedKwh,
    required this.projectedCost,
    required this.lowCost,
    required this.highCost,
    required this.rate,
    required this.daysOfData,
    required this.dailyMean,
    required this.cycleEnd,
  });

  /// Energy already used this cycle. Measured, not projected.
  final Kwh consumedSoFar;

  /// The **whole cycle**: what has been used plus what the rest of it is
  /// expected to add.
  ///
  /// This used to be the remainder alone, and the home screen labelled it
  /// "bill so far this month" — so the one number on the screen was neither
  /// what had been spent nor what the bill would be. A projection that does
  /// not say which of the two it is has no defensible reading.
  final Kwh projectedKwh;

  final Naira projectedCost;

  /// What has been used so far, priced. Carries no uncertainty band: it
  /// already happened.
  Naira get costSoFar => rate.costOf(consumedSoFar);

  Kwh get remainingKwh => projectedKwh - consumedSoFar;

  /// The range. Displayed instead of a single figure whenever data is thin —
  /// false precision on a bill projection destroys trust the first time it
  /// is wrong.
  final Naira lowCost;
  final Naira highCost;

  final Rate rate;
  final int daysOfData;
  final double dailyMean;
  final DateTime cycleEnd;

  bool get isRough => daysOfData < 14;
}

final class CostUnavailable extends CostProjection {
  const CostUnavailable(this.reason, this.readingsNeeded);
  final ForecastUnavailableReason reason;
  final int readingsNeeded;
}

/// Forecasting.
///
/// Every path returns a sealed result. There is deliberately no nullable
/// DateTime anywhere in this API: a UI cannot render "your units finish on
/// null" if the type system will not let it.
class ForecastEngine {
  const ForecastEngine({
    this.consumption = const ConsumptionEngine(),
  });

  final ConsumptionEngine consumption;

  /// Minimum clean readings before any forecast is offered.
  static const int minimumReadings = 3;

  /// Window used for the burn-rate mean.
  static const int burnRateWindowDays = 7;

  /// Projects when a prepaid balance runs out.
  BalanceForecast balance({
    required Meter meter,
    required List<Reading> readings,
    required List<Purchase> purchases,
    required DateTime now,
  }) {
    if (!meter.isPrepaid) {
      return const BalanceUnavailable(
        ForecastUnavailableReason.notPrepaid,
        0,
      );
    }

    final clean = readings.where((r) => r.isClean).toList()
      ..sort((a, b) => b.readAt.compareTo(a.readAt));

    if (clean.length < minimumReadings) {
      return BalanceUnavailable(
        ForecastUnavailableReason.notEnoughReadings,
        minimumReadings - clean.length,
      );
    }

    // On a prepaid meter the reading *is* the balance, plus anything loaded
    // since it was taken.
    final latest = clean.first;
    final loadedSince = purchases
        .where((p) =>
            p.meterId == meter.id && p.purchasedAt.isAfter(latest.readAt))
        .fold<Kwh>(Kwh.zero, (a, p) => a + (p.units ?? Kwh.zero));
    final currentBalance = latest.value + loadedSince;

    final mean = consumption.rollingDailyMean(
      meter: meter,
      readings: readings,
      purchases: purchases,
      now: now,
      days: burnRateWindowDays,
    );

    if (mean == null || mean <= 0) {
      return const BalanceUnavailable(
        ForecastUnavailableReason.noConsumptionYet,
        1,
      );
    }

    final daysRemaining = currentBalance.value / mean;
    final depletesOn =
        now.add(Duration(minutes: (daysRemaining * 24 * 60).round()));

    return BalanceKnown(
      balance: currentBalance,
      dailyMean: mean,
      depletesOn: depletesOn,
      daysRemaining: daysRemaining,
      confidenceDays: _confidenceDays(clean.length, daysRemaining),
      readingCount: clean.length,
    );
  }

  /// Projects cost to the end of the current billing cycle.
  CostProjection cost({
    required Meter meter,
    required List<Reading> readings,
    required List<Purchase> purchases,
    required Rate rate,
    required DateTime now,
    required DateTime cycleStart,
    required DateTime cycleEnd,
  }) {
    final clean = readings.where((r) => r.isClean).toList();
    if (clean.length < minimumReadings) {
      return CostUnavailable(
        ForecastUnavailableReason.notEnoughReadings,
        minimumReadings - clean.length,
      );
    }

    final mean = consumption.rollingDailyMean(
      meter: meter,
      readings: readings,
      purchases: purchases,
      now: now,
      days: 14,
    );
    if (mean == null || mean <= 0) {
      return const CostUnavailable(
        ForecastUnavailableReason.noConsumptionYet,
        1,
      );
    }

    final sorted = [...clean]..sort((a, b) => a.readAt.compareTo(b.readAt));
    final daysOfData =
        sorted.last.readAt.difference(sorted.first.readAt).inDays;

    // What the cycle has already cost, measured from readings rather than
    // modelled from the mean.
    final soFar = consumption
        .series(
          meter: meter,
          readings: readings,
          purchases: purchases,
          windowStart: cycleStart,
          windowEnd: now,
        )
        .total;

    final daysRemaining = cycleEnd.difference(now).inMinutes / (60 * 24);
    final remainder =
        Kwh.fromDouble(mean * (daysRemaining < 0 ? 0 : daysRemaining));
    final projectedKwh = soFar + remainder;

    // The band widens as data thins. With a fortnight of readings it is
    // tight; with four days it is honest about being a guess.
    final spread = daysOfData >= 14 ? 0.10 : (daysOfData >= 7 ? 0.20 : 0.35);

    // The spread applies to the remainder only. What has already been used
    // is not a guess, and widening the whole figure by 10% would put a band
    // around a measurement.
    return CostProjected(
      consumedSoFar: soFar,
      projectedKwh: projectedKwh,
      projectedCost: rate.costOf(projectedKwh),
      lowCost: rate.costOf(soFar + remainder * (1 - spread)),
      highCost: rate.costOf(soFar + remainder * (1 + spread)),
      rate: rate,
      daysOfData: daysOfData,
      dailyMean: mean,
      cycleEnd: cycleEnd,
    );
  }

  /// Confidence half-width in days. Grows with fewer readings and with a
  /// longer projection horizon — both genuinely increase uncertainty.
  double _confidenceDays(int readingCount, double daysRemaining) {
    final dataFactor = switch (readingCount) {
      < 4 => 0.35,
      < 7 => 0.22,
      < 14 => 0.14,
      _ => 0.08,
    };
    final width = daysRemaining * dataFactor;
    return width < 0.25 ? 0.25 : width;
  }
}
