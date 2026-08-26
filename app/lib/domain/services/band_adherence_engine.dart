import '../value_objects/enums.dart';
import '../value_objects/units.dart';
import 'compliance_engine.dart';

/// What a band commitment was worth, against what was actually delivered.
///
/// The compliance engine answers *were you short*. This answers *by how much,
/// and what is that worth in naira* — which is the form the question takes
/// when it reaches somebody who can do something about it.
///
/// Feature F4 in `docs/FEATURE-BACKLOG.md`. Phase 3.5.
sealed class BandAdherence {
  const BandAdherence({required this.billedBand, required this.windowDays});

  final TariffBand billedBand;
  final int windowDays;
}

/// Not enough measurement to say anything. This is a result, not an error,
/// and it is deliberately reachable: the temptation on a partly-observed
/// month is to report a satisfying number rather than an honest silence.
class AdherenceUnknown extends BandAdherence {
  const AdherenceUnknown({
    required super.billedBand,
    required super.windowDays,
    required this.coverage,
    required this.usableDays,
    required this.reason,
  });

  final double coverage;
  final int usableDays;
  final AdherenceGap reason;
}

enum AdherenceGap {
  /// Too few days observed well enough to average.
  tooFewUsableDays,

  /// Enough days, but too much of the window is unobserved for the average
  /// to survive being challenged.
  coverageTooLow,
}

/// Delivered at or above the commitment.
class AdherenceMet extends BandAdherence {
  const AdherenceMet({
    required super.billedBand,
    required super.windowDays,
    required this.measuredHours,
    required this.coverage,
    required this.usableDays,
  });

  final double measuredHours;
  final double coverage;
  final int usableDays;

  double get surplusHours => measuredHours - billedBand.committedHours;
}

/// Delivered below the commitment, with the shortfall valued.
class AdherenceShortfall extends BandAdherence {
  const AdherenceShortfall({
    required super.billedBand,
    required super.windowDays,
    required this.deliveredBand,
    required this.measuredHours,
    required this.coverage,
    required this.usableDays,
    required this.energy,
    required this.billedRate,
    required this.deliveredRate,
    required this.overpayment,
    required this.energyIsAllocated,
  });

  /// The band whose commitment the measured supply actually satisfies, or
  /// null when the measurement falls below even the lowest band.
  final TariffBand? deliveredBand;

  final double measuredHours;
  final double coverage;
  final int usableDays;

  /// Energy consumed over the window. The multiplier on the rate difference.
  final Kwh energy;

  final Rate billedRate;

  /// The rate of the band actually delivered. Null when the table has no
  /// rate for it, in which case [overpayment] is null too — a difference is
  /// not asserted from a rate that was guessed.
  final Rate? deliveredRate;

  /// What the rate difference came to over the window, or null when it
  /// cannot be computed honestly.
  final Naira? overpayment;

  /// True when the window is narrower than the reading cadence, so [energy]
  /// is partly apportioned between readings rather than read off the meter
  /// at both ends of the period. The valuation is still the best available
  /// figure; it is simply not a measurement, and the screen has to say so.
  final bool energyIsAllocated;

  double get shortfallHours => billedBand.committedHours - measuredHours;

  double get shortfallPercent =>
      billedBand.committedHours == 0
          ? 0
          : shortfallHours / billedBand.committedHours;

  /// Below the lowest published band — worth saying plainly rather than
  /// rounding up into band E.
  bool get isBelowLowestBand => deliveredBand == null;
}

class BandAdherenceEngine {
  const BandAdherenceEngine();

  /// A shortfall smaller than this is measurement noise, not a case. Matches
  /// [ComplianceEngine.breachThreshold] deliberately: two engines disagreeing
  /// about what counts as short would put two different answers on two
  /// screens of the same app.
  static const double materialShortfall = ComplianceEngine.breachThreshold;

  /// Minimum window coverage before a valuation is reported.
  static const double minimumCoverage = ComplianceEngine.minimumWindowCoverage;

  /// Minimum usable days before an average means anything.
  static const int minimumUsableDays = 7;

  /// The band whose commitment [hours] actually satisfies — the highest band
  /// the delivered service would have qualified for. Null below band E.
  static TariffBand? bandFor(double hours) {
    TariffBand? best;
    for (final band in TariffBand.values) {
      if (hours + 1e-9 >= band.committedHours) {
        if (best == null || band.committedHours > best.committedHours) {
          best = band;
        }
      }
    }
    return best;
  }

  /// [rateForBand] is injected rather than the tariff table itself: the
  /// domain layer imports nothing from `data/`, and a function is the whole
  /// dependency.
  BandAdherence evaluate({
    required TariffBand billedBand,
    required SupplySummary summary,
    required Kwh energy,
    required Rate billedRate,
    required Rate? Function(TariffBand band) rateForBand,
    bool energyIsAllocated = false,
    int windowDays = 30,
  }) {
    if (summary.usableDayCount < minimumUsableDays) {
      return AdherenceUnknown(
        billedBand: billedBand,
        windowDays: windowDays,
        coverage: summary.coverage,
        usableDays: summary.usableDayCount,
        reason: AdherenceGap.tooFewUsableDays,
      );
    }
    if (summary.coverage < minimumCoverage) {
      return AdherenceUnknown(
        billedBand: billedBand,
        windowDays: windowDays,
        coverage: summary.coverage,
        usableDays: summary.usableDayCount,
        reason: AdherenceGap.coverageTooLow,
      );
    }

    final measured = summary.rollingAverageHours;
    final shortfall = billedBand.committedHours - measured;

    if (shortfall <= billedBand.committedHours * materialShortfall) {
      return AdherenceMet(
        billedBand: billedBand,
        windowDays: windowDays,
        measuredHours: measured,
        coverage: summary.coverage,
        usableDays: summary.usableDayCount,
      );
    }

    final delivered = bandFor(measured);
    final deliveredRate = delivered == null ? null : rateForBand(delivered);

    // The difference between what the energy cost at the band billed and
    // what it would have cost at the band delivered. Computed in kobo, like
    // every other money figure, so the total is exact rather than nearly.
    Naira? overpayment;
    if (deliveredRate != null &&
        deliveredRate.koboPerKwh < billedRate.koboPerKwh) {
      final difference =
          Rate.fromKobo(billedRate.koboPerKwh - deliveredRate.koboPerKwh);
      overpayment = difference.costOf(energy);
    }

    return AdherenceShortfall(
      billedBand: billedBand,
      windowDays: windowDays,
      deliveredBand: delivered,
      measuredHours: measured,
      coverage: summary.coverage,
      usableDays: summary.usableDayCount,
      energy: energy,
      billedRate: billedRate,
      deliveredRate: deliveredRate,
      overpayment: overpayment,
      energyIsAllocated: energyIsAllocated,
    );
  }
}
