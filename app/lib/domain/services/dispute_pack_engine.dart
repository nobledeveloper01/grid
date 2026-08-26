import '../entities/meter.dart';
import '../entities/reading.dart';
import '../entities/supply_event.dart';
import '../value_objects/enums.dart';
import '../value_objects/units.dart';
import 'band_adherence_engine.dart';
import 'compliance_engine.dart';
import 'consumption_engine.dart';

/// What the pack is arguing.
///
/// Four, because four is what the evidence Grid holds can actually support.
/// A fifth template that the data cannot substantiate would be worse than
/// having four: it would send somebody into a formal process with a document
/// that falls apart on the first question.
enum PackKind {
  bandShortfall(
    'Band shortfall',
    'You are billed for a band you are not receiving.',
  ),
  estimatedBill(
    'Disputed bill',
    'A bill that does not match what your meter recorded.',
  ),
  prolongedOutage(
    'Prolonged outage',
    'A specific outage, with the log that shows how long it ran.',
  ),
  consumptionRecord(
    'Consumption record',
    'A plain statement of your readings and usage for a period.',
  );

  const PackKind(this.label, this.description);
  final String label;
  final String description;

  /// Whether this template argues something, as opposed to simply attesting
  /// to a record. A record needs no claim and no remedy.
  bool get isClaim => this != PackKind.consumptionRecord;
}

/// Why a pack cannot be built.
enum PackBlock {
  /// Fewer than [DisputePackEngine.minimumDays] of record. A pack built on a
  /// week of data invites the response that a week proves nothing, and the
  /// user only gets one first impression at a DisCo office.
  tooShort,

  /// Not enough readings to derive consumption at all.
  tooFewReadings,

  /// The supply log does not cover enough of the period to state hours.
  supplyCoverageTooLow,

  /// The meter has no band, so there is no commitment to measure against.
  noBand,
}

sealed class PackEligibility {
  const PackEligibility();
}

class PackReady extends PackEligibility {
  const PackReady();
}

class PackBlocked extends PackEligibility {
  const PackBlocked(this.reason, this.detail);

  final PackBlock reason;

  /// Plain-language specifics, so the screen never has to invent them.
  final String detail;
}

/// One reading, and whether it is in the pack.
///
/// Exclusions carry a reason and are printed. A pack that quietly drops the
/// inconvenient readings is a pack whose author can be accused of doing
/// exactly that, and the accusation would be true.
class EvidenceItem {
  const EvidenceItem({
    required this.reading,
    required this.isIncluded,
    this.exclusionReason,
    this.flagNote,
  });

  final Reading reading;
  final bool isIncluded;

  /// Why this reading is not in the figures. Set only when excluded.
  final String? exclusionReason;

  /// A caveat on a reading that *is* in the figures.
  ///
  /// Not every flag disqualifies a reading — a low-confidence OCR read or a
  /// value the user corrected still counts towards consumption. But an
  /// included flagged reading that the pack presents as unremarkable is
  /// exactly the thing the phase 5 gate forbids: flagged readings are
  /// excluded, or they are shown flagged. There is no third option where
  /// they are quietly included as clean.
  final String? flagNote;

  /// Anything the pack has to say about this reading, either way.
  String? get note => exclusionReason ?? flagNote;

  bool get isFlagged => reading.flagSet.isNotEmpty;
}

/// How finely the supply log is printed.
///
/// A year of daily rows is 365 lines nobody reads, and it overran the PDF
/// engine's page limit outright — the twelve-month pack, which is exactly the
/// period a serious dispute uses, failed to generate at all. Beyond a couple
/// of months the log is rolled up, and the days that actually carry the
/// complaint are listed separately.
enum SupplyDetail {
  daily,
  weekly,
  monthly;

  String get label => switch (this) {
        SupplyDetail.daily => 'Day by day',
        SupplyDetail.weekly => 'Week by week',
        SupplyDetail.monthly => 'Month by month',
      };
}

/// One row of the printed supply log — a day, a week or a month.
class PackSupplyBucket {
  const PackSupplyBucket({
    required this.label,
    required this.start,
    required this.end,
    required this.meanHoursPerDay,
    required this.coverage,
    required this.usableDays,
    required this.totalDays,
  });

  final String label;
  final DateTime start;
  final DateTime end;

  /// Mean supply hours across the usable days in this bucket. Days that were
  /// not observed well enough are excluded from the mean rather than counted
  /// as zero hours, which would be a fabricated outage.
  final double meanHoursPerDay;

  final double coverage;
  final int usableDays;
  final int totalDays;

  bool get isUsable => usableDays > 0;
}

/// A day of the supply log, as it appears in the pack.
class PackSupplyDay {
  const PackSupplyDay({
    required this.date,
    required this.hoursOn,
    required this.coverage,
    required this.isUsable,
  });

  final DateTime date;
  final double hoursOn;
  final double coverage;
  final bool isUsable;
}

/// Everything a pack contains, assembled and ready to render.
///
/// Pure data. The PDF layer turns it into pages and adds nothing — every
/// figure and every caveat is decided here, where it is testable, rather
/// than in a widget tree nobody can assert against.
class DisputePack {
  const DisputePack({
    required this.kind,
    required this.meter,
    required this.periodStart,
    required this.periodEnd,
    required this.generatedAt,
    required this.evidence,
    required this.consumption,
    required this.supplyDays,
    required this.supplyDetail,
    required this.supplyBuckets,
    required this.worstDays,
    required this.supplyCoverage,
    required this.readingCoverage,
    required this.adherence,
    required this.disputedAmount,
    required this.narrative,
    required this.photoHashes,
  });

  final PackKind kind;
  final Meter meter;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime generatedAt;

  final List<EvidenceItem> evidence;
  final ConsumptionSeries consumption;
  /// Every day, at full fidelity. Not all of it is printed.
  final List<PackSupplyDay> supplyDays;

  final SupplyDetail supplyDetail;

  /// What the pack actually prints as its supply log.
  final List<PackSupplyBucket> supplyBuckets;

  /// The worst observed days, listed whenever the log is rolled up — a
  /// monthly average hides the days the complaint is actually about.
  final List<PackSupplyDay> worstDays;

  /// Proportion of the period the supply log observed.
  final double supplyCoverage;

  /// Proportion of the period spanned by reading intervals.
  final double readingCoverage;

  /// Present on a band-shortfall pack.
  final BandAdherence? adherence;

  /// Present on a disputed-bill pack: what the DisCo asked for.
  final Naira? disputedAmount;

  /// The user's own account of what happened, in their words. Optional, and
  /// printed verbatim — Grid does not rewrite it.
  final String? narrative;

  /// SHA-256 of every retained photograph, printed so the images can be
  /// shown to be the ones the record refers to.
  final Map<String, String> photoHashes;

  int get days => periodEnd.difference(periodStart).inDays;

  List<EvidenceItem> get included =>
      evidence.where((e) => e.isIncluded).toList();

  List<EvidenceItem> get excluded =>
      evidence.where((e) => !e.isIncluded).toList();

  /// What the energy in the period cost at the rate in force.
  Naira costAt(Rate rate) => rate.costOf(consumption.total);
}

/// Assembles a dispute pack from the record.
class DisputePackEngine {
  const DisputePackEngine();

  /// No pack from less than a fortnight.
  static const int minimumDays = 14;

  /// A band-shortfall pack needs the supply log to have seen this much of
  /// the period. Matches the compliance engine's alerting floor.
  static const double minimumSupplyCoverage =
      ComplianceEngine.minimumWindowCoverage;

  PackEligibility check({
    required PackKind kind,
    required Meter meter,
    required List<Reading> readings,
    required List<SupplyEvent> supply,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime now,
  }) {
    final days = periodEnd.difference(periodStart).inDays;
    if (days < minimumDays) {
      return PackBlocked(
        PackBlock.tooShort,
        'A pack covers at least $minimumDays days. This period is '
        '$days ${days == 1 ? 'day' : 'days'} long.',
      );
    }

    if (kind != PackKind.prolongedOutage) {
      final usable = readings
          .where((r) => !r.isSuperseded && r.isClean)
          .where((r) =>
              !r.readAt.isBefore(periodStart) && !r.readAt.isAfter(periodEnd))
          .length;
      if (usable < 2) {
        return PackBlocked(
          PackBlock.tooFewReadings,
          'Two clean readings inside the period are the minimum — Grid has '
          '$usable. Log another and the pack becomes available.',
        );
      }
    }

    if (kind == PackKind.bandShortfall) {
      if (meter.tariffBand == null) {
        return const PackBlocked(
          PackBlock.noBand,
          'This meter has no tariff band set, so there is no promise to '
          'measure the supply against.',
        );
      }
      final summary = const ComplianceEngine().summarise(
        events: supply,
        windowStart: periodStart,
        windowEnd: periodEnd,
        now: now,
      );
      if (summary.coverage < minimumSupplyCoverage) {
        return PackBlocked(
          PackBlock.supplyCoverageTooLow,
          'The power log covers '
          '${(summary.coverage * 100).round()}% of this period. A shortfall '
          'claim needs at least '
          '${(minimumSupplyCoverage * 100).round()}%, or the first question '
          'asked will be about the gaps.',
        );
      }
    }

    return const PackReady();
  }

  /// Builds the pack. Call [check] first — this assumes it passed.
  DisputePack build({
    required PackKind kind,
    required Meter meter,
    required List<Reading> readings,
    required List<Purchase> purchases,
    required List<SupplyEvent> supply,
    required DateTime periodStart,
    required DateTime periodEnd,
    required DateTime now,
    Rate? billedRate,
    Rate? Function(TariffBand band)? rateForBand,
    Naira? disputedAmount,
    String? narrative,
  }) {
    final inPeriod = readings
        .where((r) => !r.isSuperseded)
        .where((r) =>
            !r.readAt.isBefore(periodStart) && !r.readAt.isAfter(periodEnd))
        .toList()
      ..sort((a, b) => a.readAt.compareTo(b.readAt));

    final evidence = [
      for (final r in inPeriod)
        EvidenceItem(
          reading: r,
          isIncluded: r.isClean,
          exclusionReason: r.isClean ? null : _reasonFor(r),
          flagNote: r.isClean && r.flagSet.isNotEmpty ? _reasonFor(r) : null,
        ),
    ];

    final consumption = const ConsumptionEngine().series(
      meter: meter,
      readings: readings,
      purchases: purchases,
      windowStart: periodStart,
      windowEnd: periodEnd,
    );

    final summary = const ComplianceEngine().summarise(
      events: supply,
      windowStart: periodStart,
      windowEnd: periodEnd,
      now: now,
    );

    final supplyDays = [
      for (final d in summary.days)
        PackSupplyDay(
          date: d.date,
          hoursOn: d.hours,
          coverage: d.coverage,
          isUsable: d.isUsable,
        ),
    ];

    final detail = detailFor(supplyDays.length);
    final buckets = bucket(supplyDays, detail);
    final worst = detail == SupplyDetail.daily
        ? const <PackSupplyDay>[]
        : worstOf(supplyDays);

    BandAdherence? adherence;
    final band = meter.tariffBand;
    if (kind == PackKind.bandShortfall &&
        band != null &&
        billedRate != null &&
        rateForBand != null) {
      adherence = const BandAdherenceEngine().evaluate(
        billedBand: band,
        summary: summary,
        energy: consumption.total,
        billedRate: billedRate,
        rateForBand: rateForBand,
        energyIsAllocated: consumption.daily.any((d) => d.isInterpolated),
        windowDays: periodEnd.difference(periodStart).inDays,
      );
    }

    return DisputePack(
      kind: kind,
      meter: meter,
      periodStart: periodStart,
      periodEnd: periodEnd,
      generatedAt: now,
      evidence: evidence,
      consumption: consumption,
      supplyDays: supplyDays,
      supplyDetail: detail,
      supplyBuckets: buckets,
      worstDays: worst,
      supplyCoverage: summary.coverage,
      readingCoverage: consumption.coverage,
      adherence: adherence,
      disputedAmount: disputedAmount,
      narrative: narrative,
      photoHashes: {
        for (final e in evidence)
          if (e.reading.photoSha256 != null)
            e.reading.id: e.reading.photoSha256!,
      },
    );
  }

  /// Above this many days the daily log is rolled up.
  static const int maxDailyRows = 45;

  /// And above this, rolled up further still.
  static const int maxWeeklyRows = 200;

  /// How many of the worst days a rolled-up pack calls out by name.
  static const int worstDayCount = 10;

  static SupplyDetail detailFor(int days) {
    if (days <= maxDailyRows) return SupplyDetail.daily;
    if (days <= maxWeeklyRows) return SupplyDetail.weekly;
    return SupplyDetail.monthly;
  }

  /// Groups days into printed rows.
  ///
  /// The mean is over usable days only. Counting an unobserved day as zero
  /// hours would manufacture an outage, which is the one direction this
  /// product must never round in — even though it is the direction that
  /// flatters the user's own case.
  List<PackSupplyBucket> bucket(
    List<PackSupplyDay> days,
    SupplyDetail detail,
  ) {
    if (days.isEmpty) return const [];

    if (detail == SupplyDetail.daily) {
      return [
        for (final d in days)
          PackSupplyBucket(
            label: _shortDate(d.date),
            start: d.date,
            end: d.date,
            meanHoursPerDay: d.hoursOn,
            coverage: d.coverage,
            usableDays: d.isUsable ? 1 : 0,
            totalDays: 1,
          ),
      ];
    }

    final groups = <String, List<PackSupplyDay>>{};
    final order = <String>[];
    for (final d in days) {
      final key = detail == SupplyDetail.weekly
          ? _weekKey(d.date)
          : '${d.date.year}-${d.date.month.toString().padLeft(2, '0')}';
      if (!groups.containsKey(key)) order.add(key);
      groups.putIfAbsent(key, () => []).add(d);
    }

    return [
      for (final key in order)
        () {
          final members = groups[key]!;
          final usable = members.where((d) => d.isUsable).toList();
          final observed =
              members.fold<double>(0, (a, d) => a + d.coverage) /
                  members.length;
          return PackSupplyBucket(
            label: detail == SupplyDetail.weekly
                ? '${_shortDate(members.first.date)} – '
                    '${_shortDate(members.last.date)}'
                : '${_monthName(members.first.date)} '
                    '${members.first.date.year}',
            start: members.first.date,
            end: members.last.date,
            meanHoursPerDay: usable.isEmpty
                ? 0
                : usable.fold<double>(0, (a, d) => a + d.hoursOn) /
                    usable.length,
            coverage: observed,
            usableDays: usable.length,
            totalDays: members.length,
          );
        }(),
    ];
  }

  /// The observed days with the least supply. Ties broken by date so the
  /// same record always produces the same pack.
  List<PackSupplyDay> worstOf(List<PackSupplyDay> days) {
    final usable = days.where((d) => d.isUsable).toList()
      ..sort((a, b) {
        final byHours = a.hoursOn.compareTo(b.hoursOn);
        return byHours != 0 ? byHours : a.date.compareTo(b.date);
      });
    return usable.take(worstDayCount).toList();
  }

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  static String _monthName(DateTime d) => _months[d.month - 1];

  static String _shortDate(DateTime d) =>
      '${d.day} ${_monthName(d).substring(0, 3)}';

  static String _weekKey(DateTime d) {
    final dayOfYear = d.difference(DateTime(d.year)).inDays;
    return '${d.year}-w${(dayOfYear / 7).floor()}';
  }

  /// Plain language, not enum names. This text is printed and read aloud by
  /// somebody defending their own record.
  String _reasonFor(Reading r) {
    final flags = r.flagSet;
    if (flags.contains(ReadingFlag.anomalousHigh)) {
      return 'Jumped far above the usual pattern — excluded so it cannot be '
          'said to inflate the figures.';
    }
    if (flags.contains(ReadingFlag.anomalousZero)) {
      return 'Recorded as zero or lower than the reading before it.';
    }
    if (flags.contains(ReadingFlag.rolloverOrReplacement)) {
      return 'Taken across a meter rollover or a meter change.';
    }
    if (flags.contains(ReadingFlag.digitCountMismatch)) {
      return 'Digit count does not match the meter, so the value may be '
          'misread.';
    }
    if (flags.contains(ReadingFlag.duplicateWindow)) {
      return 'A second reading taken in the same window as another.';
    }
    if (flags.contains(ReadingFlag.lowOcrConfidence)) {
      return 'Read from a photograph the app was not confident about; the '
          'value was accepted by the account holder.';
    }
    if (flags.contains(ReadingFlag.userEdited)) {
      return 'Corrected by the account holder after it was first entered. '
          'The original entry is retained in the record.';
    }
    return 'Flagged during entry.';
  }
}
