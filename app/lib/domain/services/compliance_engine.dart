import '../entities/supply_event.dart';
import '../value_objects/enums.dart';

/// One day's supply availability, with the coverage that produced it.
class DailySupply {
  const DailySupply({
    required this.date,
    required this.availableMinutes,
    required this.unavailableMinutes,
    required this.unknownMinutes,
  });

  final DateTime date;
  final int availableMinutes;
  final int unavailableMinutes;
  final int unknownMinutes;

  int get knownMinutes => availableMinutes + unavailableMinutes;

  double get hours => availableMinutes / 60.0;

  /// Proportion of the day we actually have data for, 0–1.
  double get coverage => knownMinutes / (24 * 60);

  /// Days below this coverage are excluded from compliance scoring and from
  /// dispute packs. A day we barely observed cannot support a claim.
  static const double minimumCoverage = 0.60;

  bool get isUsable => coverage >= minimumCoverage;
}

class SupplySummary {
  const SupplySummary({
    required this.days,
    required this.rollingAverageHours,
    required this.coverage,
    required this.usableDayCount,
  });

  final List<DailySupply> days;

  /// Mean daily supply hours across usable days only.
  final double rollingAverageHours;

  /// Mean coverage across the whole window.
  final double coverage;

  final int usableDayCount;

  bool get hasEnoughData => usableDayCount >= 7;
}

/// The result of comparing measured supply against a band commitment.
class ComplianceResult {
  const ComplianceResult({
    required this.band,
    required this.summary,
    required this.shortfallHours,
    required this.isBreach,
    required this.canRaiseAlert,
  });

  final TariffBand band;
  final SupplySummary summary;

  /// Committed hours minus measured hours. Positive means short.
  final double shortfallHours;

  final bool isBreach;

  /// Whether the evidence is strong enough to raise an alert and offer to
  /// build a case. Requires both a material shortfall and enough coverage.
  final bool canRaiseAlert;

  double get shortfallPercent =>
      band.committedHours == 0 ? 0 : shortfallHours / band.committedHours;
}

/// Computes daily supply hours, coverage, and band compliance.
///
/// The important property here is honesty. Periods with no samples are
/// counted as `unknown` and excluded from both numerator and denominator —
/// never interpolated into whichever state would be convenient.
class ComplianceEngine {
  const ComplianceEngine();

  /// A shortfall below this fraction of the commitment is noise, not a case.
  static const double breachThreshold = 0.10;

  /// Minimum window coverage before an alert may be raised.
  static const double minimumWindowCoverage = 0.70;

  /// Hysteresis: once alerted, do not alert again for this long.
  static const Duration alertCooldown = Duration(days: 14);

  SupplySummary summarise({
    required List<SupplyEvent> events,
    required DateTime windowStart,
    required DateTime windowEnd,
    required DateTime now,
  }) {
    final active = events.where((e) => !e.isSuperseded).toList();
    final days = <DailySupply>[];

    var cursor = DateTime(windowStart.year, windowStart.month, windowStart.day);
    final last = DateTime(windowEnd.year, windowEnd.month, windowEnd.day);

    while (!cursor.isAfter(last)) {
      final dayStart = cursor;
      final dayEnd = cursor.add(const Duration(days: 1));

      var available = 0;
      var unavailable = 0;

      for (final e in active) {
        final minutes = e.overlapMinutes(dayStart, dayEnd, now);
        if (minutes == 0) continue;
        switch (e.state) {
          case SupplyState.available:
            available += minutes;
          case SupplyState.unavailable:
            unavailable += minutes;
          case SupplyState.unknown:
            break;
        }
      }

      // Anything not covered by an event is unknown. We do not guess.
      final accounted = available + unavailable;
      final unknown = (24 * 60) - accounted;

      days.add(DailySupply(
        date: dayStart,
        availableMinutes: available,
        unavailableMinutes: unavailable,
        unknownMinutes: unknown < 0 ? 0 : unknown,
      ));

      cursor = dayEnd;
    }

    final usable = days.where((d) => d.isUsable).toList();
    final average = usable.isEmpty
        ? 0.0
        : usable.fold<double>(0, (a, d) => a + d.hours) / usable.length;
    final coverage = days.isEmpty
        ? 0.0
        : days.fold<double>(0, (a, d) => a + d.coverage) / days.length;

    return SupplySummary(
      days: days,
      rollingAverageHours: average,
      coverage: coverage,
      usableDayCount: usable.length,
    );
  }

  ComplianceResult evaluate({
    required TariffBand band,
    required List<SupplyEvent> events,
    required DateTime now,
    int windowDays = 30,
  }) {
    final summary = summarise(
      events: events,
      windowStart: now.subtract(Duration(days: windowDays)),
      windowEnd: now,
      now: now,
    );

    final shortfall = band.committedHours - summary.rollingAverageHours;
    final isBreach = summary.hasEnoughData &&
        shortfall > band.committedHours * breachThreshold;

    return ComplianceResult(
      band: band,
      summary: summary,
      shortfallHours: shortfall,
      isBreach: isBreach,
      canRaiseAlert:
          isBreach && summary.coverage >= minimumWindowCoverage,
    );
  }

  /// Whether an alert may fire, given when one last did. Hysteresis exists
  /// so a supply figure hovering around the threshold does not produce a
  /// notification every day.
  bool shouldAlert({
    required ComplianceResult result,
    required DateTime now,
    DateTime? lastAlertedAt,
  }) {
    if (!result.canRaiseAlert) return false;
    if (lastAlertedAt == null) return true;
    return now.difference(lastAlertedAt) >= alertCooldown;
  }
}
