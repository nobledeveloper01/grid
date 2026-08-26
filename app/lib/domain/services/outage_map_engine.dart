import '../entities/supply_event.dart';
import '../value_objects/enums.dart';
import 'compliance_engine.dart';

/// Turning one household's supply log into something that can be shared
/// without identifying the household.
///
/// Phase 7. A single household's outage record proves that household was out.
/// Several households on the same feeder, saying the same thing about the same
/// hours, prove the *feeder* was out — which is a materially stronger claim and
/// one no individual can make alone.
///
/// The exit gate is a privacy constraint, and it is the whole design:
///
/// > **No individual location leaves the device at finer than LGA
/// > granularity.**
///
/// That rules out coordinates, it rules out an address, and it rules out a
/// meter number — which is unique, printed on the meter, and would let anyone
/// holding the aggregate walk the data back to a person. What leaves is an
/// LGA, a DisCo, a day, and hours. Nothing that identifies who reported it.
class OutageReport {
  const OutageReport({
    required this.lga,
    required this.disco,
    required this.date,
    required this.hoursWithSupply,
    required this.coverage,
    required this.band,
  });

  /// Local government area. Coarse by construction — Surulere holds hundreds
  /// of thousands of people.
  final String lga;

  final DisCo disco;

  /// The day, with no time component. A timestamp to the minute is close to a
  /// fingerprint when combined with an LGA and a band.
  final DateTime date;

  final double hoursWithSupply;

  /// How much of the day was observed. Travels with the figure, because an
  /// aggregate built from unobserved days would be the same fabrication at
  /// community scale that Grid refuses at household scale.
  final double coverage;

  /// The band claimed, so a shortfall can be aggregated against a promise.
  final TariffBand? band;

  Map<String, dynamic> toJson() => {
        'lga': lga,
        'disco': disco.name,
        'date': date.toIso8601String().split('T').first,
        'hours': double.parse(hoursWithSupply.toStringAsFixed(1)),
        'coverage': double.parse(coverage.toStringAsFixed(2)),
        'band': band?.name,
      };
}

/// Why a household cannot contribute.
enum ContributionGap {
  /// No LGA recorded, so there is nothing to aggregate by.
  noArea,

  /// Nothing measured well enough to be worth sharing.
  noUsableDays,
}

sealed class ContributionResult {
  const ContributionResult();
}

class ContributionReady extends ContributionResult {
  const ContributionReady(this.reports);
  final List<OutageReport> reports;
}

class ContributionBlocked extends ContributionResult {
  const ContributionBlocked(this.reason, this.detail);
  final ContributionGap reason;
  final String detail;
}

class OutageMapEngine {
  const OutageMapEngine();

  /// A day below this is not shared. The same floor the compliance engine
  /// uses: a day nobody observed properly is not evidence, and pooling it
  /// with others does not make it so.
  static const double minimumCoverage = DailySupply.minimumCoverage;

  /// Builds what this household would contribute, if it chose to.
  ///
  /// Nothing here sends anything. It returns the payload so a screen can show
  /// the user *exactly* what would leave the device before they agree to it —
  /// which is the only honest way to ask for this.
  ContributionResult prepare({
    required String? lga,
    required DisCo disco,
    required TariffBand? band,
    required List<SupplyEvent> events,
    required DateTime windowStart,
    required DateTime windowEnd,
    required DateTime now,
  }) {
    final area = lga?.trim();
    if (area == null || area.isEmpty) {
      return const ContributionBlocked(
        ContributionGap.noArea,
        'Grid needs your local government area to pool your log with your '
        'neighbours’. It is the only location that ever leaves the device — '
        'never an address, never a meter number, never coordinates.',
      );
    }

    final summary = const ComplianceEngine().summarise(
      events: events,
      windowStart: windowStart,
      windowEnd: windowEnd,
      now: now,
    );

    final reports = [
      for (final day in summary.days)
        if (day.isUsable)
          OutageReport(
            lga: area,
            disco: disco,
            date: DateTime(day.date.year, day.date.month, day.date.day),
            hoursWithSupply: day.hours,
            coverage: day.coverage,
            band: band,
          ),
    ];

    if (reports.isEmpty) {
      return const ContributionBlocked(
        ContributionGap.noUsableDays,
        'None of the days in this window were measured well enough to be '
        'worth pooling. A day nobody observed is not evidence, and adding it '
        'to other people’s would not make it so.',
      );
    }

    return ContributionReady(reports);
  }

  /// What a household would be agreeing to send, in their own words.
  ///
  /// Generated from the payload rather than written as static copy, so it
  /// cannot drift from what is actually transmitted — a consent screen that
  /// describes an older version of the payload is worse than none.
  List<String> describe(List<OutageReport> reports) {
    if (reports.isEmpty) return const [];
    final first = reports.first;
    return [
      'Your local government area: ${first.lga}',
      'Your distribution company: ${first.disco.label}',
      if (first.band != null) 'Your tariff band: Band ${first.band!.label}',
      '${reports.length} days of supply hours, one figure per day',
      'How much of each day Grid actually observed',
    ];
  }

  /// And what would not.
  List<String> describeWithheld() => const [
        'Your address',
        'Your meter number',
        'Your name, phone number or email — Grid has never had these',
        'Any location finer than the LGA',
        'The times of day your power was on or off',
        'Your readings, purchases, or anything about what you spend',
      ];

  /// Pools reports from several households into a feeder-level picture.
  ///
  /// Runs on whatever aggregate the device holds, so the same code produces
  /// the view whether the reports came from a server or from a file somebody
  /// shared. Days are keyed by LGA, DisCo and date — the only fields that
  /// exist.
  List<AreaDay> aggregate(List<OutageReport> reports) {
    final byKey = <String, List<OutageReport>>{};
    for (final r in reports) {
      final key = '${r.lga}|${r.disco.name}|'
          '${r.date.toIso8601String().split('T').first}';
      byKey.putIfAbsent(key, () => []).add(r);
    }

    final out = [
      for (final entry in byKey.entries)
        () {
          final group = entry.value;
          final hours = group.map((r) => r.hoursWithSupply).toList()..sort();
          return AreaDay(
            lga: group.first.lga,
            disco: group.first.disco,
            date: group.first.date,
            households: group.length,
            medianHours: _median(hours),
            worstHours: hours.first,
            bestHours: hours.last,
          );
        }(),
    ]..sort((a, b) => b.date.compareTo(a.date));

    return out;
  }

  /// Median rather than mean. One household with a generator-fed meter or a
  /// misconfigured log would drag an average; the median is what most of the
  /// street actually saw.
  double _median(List<double> sorted) {
    if (sorted.isEmpty) return 0;
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}

/// One area, one day, as several households saw it.
class AreaDay {
  const AreaDay({
    required this.lga,
    required this.disco,
    required this.date,
    required this.households,
    required this.medianHours,
    required this.worstHours,
    required this.bestHours,
  });

  final String lga;
  final DisCo disco;
  final DateTime date;

  /// How many logs this rests on. Printed everywhere the figure is, because
  /// "four hours across two households" and "four hours across two hundred"
  /// are not the same claim.
  final int households;

  final double medianHours;
  final double worstHours;
  final double bestHours;

  /// Below this the day is shown but not treated as representative. Two
  /// households on one street are not a feeder.
  static const int credibleAt = 5;

  bool get isCredible => households >= credibleAt;

  /// The spread. A wide one means the outage was not shared — which usually
  /// means the problem was in a house rather than on the line, and saying so
  /// stops somebody taking a feeder complaint to a DisCo about their own
  /// wiring.
  double get spread => bestHours - worstHours;
}
