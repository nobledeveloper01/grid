import '../entities/supply_event.dart';
import '../value_objects/enums.dart';

/// One day's supply availability, with the coverage that produced it.
class DailySupply {
  const DailySupply({
    required this.date,
    required this.availableMinutes,
    required this.unavailableMinutes,
    required this.unknownMinutes,
    this.observableMinutes = fullDay,
  });

  static const int fullDay = 24 * 60;

  final DateTime date;
  final int availableMinutes;
  final int unavailableMinutes;
  final int unknownMinutes;

  /// How much of this day *could* have been observed. A full day for every
  /// day but the current one, which is only as long as the clock has run.
  ///
  /// Without this, today is scored against 24 hours it has not had yet: a
  /// perfectly observed morning reports 12% coverage at 03:00, drags the
  /// window average down, and can push an otherwise sound case below the
  /// coverage floor that decides whether it may be stated at all.
  final int observableMinutes;

  int get knownMinutes => availableMinutes + unavailableMinutes;

  double get hours => availableMinutes / 60.0;

  /// Proportion of the observable day we actually have data for, 0–1.
  double get coverage =>
      observableMinutes <= 0 ? 0 : knownMinutes / observableMinutes;

  /// True for a day still in progress.
  bool get isPartialDay => observableMinutes < fullDay;

  /// Days below this coverage are excluded from compliance scoring and from
  /// dispute packs. A day we barely observed cannot support a claim.
  static const double minimumCoverage = 0.60;

  /// Usable as one day of supply hours in an average.
  ///
  /// A day in progress is never usable, however well observed: eight hours
  /// of power by lunchtime is not an eight-hour day, and averaging it in as
  /// one would understate every figure the product reports.
  bool get isUsable => !isPartialDay && coverage >= minimumCoverage;
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

      // How much of this day the clock has actually reached.
      final observable = now.isAfter(dayEnd)
          ? DailySupply.fullDay
          : now.isBefore(dayStart)
              ? 0
              : now.difference(dayStart).inMinutes;

      // Anything not covered by an event is unknown. We do not guess.
      final accounted = available + unavailable;
      final unknown = observable - accounted;

      days.add(DailySupply(
        date: dayStart,
        availableMinutes: available,
        unavailableMinutes: unavailable,
        unknownMinutes: unknown < 0 ? 0 : unknown,
        observableMinutes: observable,
      ));

      cursor = dayEnd;
    }

    final usable = days.where((d) => d.isUsable).toList();
    final average = usable.isEmpty
        ? 0.0
        : usable.fold<double>(0, (a, d) => a + d.hours) / usable.length;
    // Weighted by observable minutes rather than by day, so a window ending
    // at 03:00 is not judged as though its last day were a full one.
    final observable = days.fold<int>(0, (a, d) => a + d.observableMinutes);
    final known = days.fold<int>(0, (a, d) => a + d.knownMinutes);
    final coverage = observable == 0 ? 0.0 : known / observable;

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

  /// The longest continuous outage actually observed in a window.
  ///
  /// A battery is sized on this, not on the average — an average-sized bank is
  /// flat precisely on the days the household bought it for. Only closed
  /// `unavailable` periods count: an open one is still running and its length
  /// is a fact about the clock rather than about the grid.
  double longestOutageHours({
    required List<SupplyEvent> events,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    var longest = 0.0;
    for (final e in events) {
      if (e.isSuperseded || e.state != SupplyState.unavailable) continue;
      final end = e.endedAt;
      if (end == null) continue;
      if (end.isBefore(windowStart) || e.startedAt.isAfter(windowEnd)) {
        continue;
      }
      final from = e.startedAt.isBefore(windowStart) ? windowStart : e.startedAt;
      final to = end.isAfter(windowEnd) ? windowEnd : end;
      final hours = to.difference(from).inMinutes / 60.0;
      if (hours > longest) longest = hours;
    }
    return longest;
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
