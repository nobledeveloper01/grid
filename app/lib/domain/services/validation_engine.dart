import '../entities/meter.dart';
import '../entities/reading.dart';
import '../value_objects/enums.dart';
import '../value_objects/units.dart';

enum WarningSeverity { info, caution, serious }

/// A remedy offered alongside a warning. The UI renders these as buttons and
/// never has to know the business rule behind them.
enum WarningRemedy {
  reEnter,
  confirmAnyway,
  meterWasReplaced,
  checkDecimalPoint,
  reject,
}

/// A validation finding.
///
/// Never an exception, never a bare bool. Every warning carries a message,
/// a severity, an ordered list of remedies, and the flag to record if the
/// user proceeds — so the presentation layer renders it without embedding
/// any business rule.
class ValidationWarning {
  const ValidationWarning({
    required this.message,
    required this.severity,
    required this.remedies,
    this.flagIfConfirmed,
  });

  final String message;
  final WarningSeverity severity;
  final List<WarningRemedy> remedies;
  final ReadingFlag? flagIfConfirmed;

  /// A warning never hard-blocks. The only exception is an out-of-order
  /// reading, which is rejected because readings are append-only in time
  /// order and accepting one would corrupt every derived figure.
  bool get isBlocking => remedies.length == 1 && remedies.first == WarningRemedy.reject;
}

class ValidationOutcome {
  const ValidationOutcome(this.warnings);
  final List<ValidationWarning> warnings;

  static const clean = ValidationOutcome(<ValidationWarning>[]);

  bool get isClean => warnings.isEmpty;
  bool get isBlocked => warnings.any((w) => w.isBlocking);

  /// The flags to record if the user confirms despite the warnings.
  int get flagsIfConfirmed => warnings
      .map((w) => w.flagIfConfirmed)
      .whereType<ReadingFlag>()
      .fold(0, (acc, f) => acc.withFlag(f));
}

/// Implements the FR-2.3 validation rule table.
///
/// Pure. No I/O, no Flutter, no exceptions. Deterministic for a given
/// (meter, candidate, history).
class ValidationEngine {
  const ValidationEngine();

  /// Multiplier over the rolling daily mean above which a reading is flagged
  /// as anomalously high.
  static const double anomalyMultiplier = 4.0;

  /// Days of logged supply with zero consumption before we flag it.
  static const int zeroConsumptionDays = 3;

  /// A repeat of the previous value inside this window is accepted but does
  /// not trigger recomputation.
  static const Duration duplicateWindow = Duration(hours: 6);

  ValidationOutcome validate({
    required Meter meter,
    required Kwh candidate,
    required DateTime readAt,
    required List<Reading> history,
    double? rollingDailyMeanKwh,
    bool supplyWasAvailable = true,
  }) {
    final warnings = <ValidationWarning>[];

    // History must be newest-first for the comparisons below.
    final sorted = [...history.where((r) => !r.isSuperseded)]
      ..sort((a, b) => b.readAt.compareTo(a.readAt));

    if (sorted.isEmpty) {
      return ValidationOutcome(warnings);
    }

    final previous = sorted.first;

    // Readings are append-only in time order. An out-of-order entry would
    // corrupt every derived figure, so this is the one hard rejection.
    if (readAt.isBefore(previous.readAt)) {
      warnings.add(const ValidationWarning(
        message: "This reading is dated before your last one. "
            "Readings have to be entered in the order you took them.",
        severity: WarningSeverity.serious,
        remedies: [WarningRemedy.reject],
      ));
      return ValidationOutcome(warnings);
    }

    // A repeat inside the duplicate window: accept silently, but mark it so
    // forecasts are not recomputed off a non-observation.
    if (candidate.milli == previous.value.milli &&
        readAt.difference(previous.readAt) < duplicateWindow) {
      warnings.add(const ValidationWarning(
        message: 'Same as your last reading, taken a few hours ago.',
        severity: WarningSeverity.info,
        remedies: [WarningRemedy.confirmAnyway],
        flagIfConfirmed: ReadingFlag.duplicateWindow,
      ));
      return ValidationOutcome(warnings);
    }

    _checkDirection(meter, candidate, previous, warnings);
    _checkDigitCount(candidate, previous, warnings);
    _checkMagnitude(
      meter: meter,
      candidate: candidate,
      previous: previous,
      readAt: readAt,
      rollingDailyMeanKwh: rollingDailyMeanKwh,
      supplyWasAvailable: supplyWasAvailable,
      warnings: warnings,
    );

    return ValidationOutcome(warnings);
  }

  void _checkDirection(
    Meter meter,
    Kwh candidate,
    Reading previous,
    List<ValidationWarning> warnings,
  ) {
    switch (meter.direction) {
      case MeterDirection.incrementing:
        if (candidate < previous.value) {
          warnings.add(const ValidationWarning(
            message: "This is lower than your last reading. "
                "Meters count up. Did you read it correctly?",
            severity: WarningSeverity.serious,
            remedies: [
              WarningRemedy.reEnter,
              WarningRemedy.meterWasReplaced,
              WarningRemedy.confirmAnyway,
            ],
            flagIfConfirmed: ReadingFlag.rolloverOrReplacement,
          ));
        }
      case MeterDirection.decrementing:
        if (candidate > previous.value) {
          warnings.add(const ValidationWarning(
            message: "This is higher than your last reading. On a prepaid "
                "meter the number goes down as you use power. Did you load "
                "units since the last reading?",
            severity: WarningSeverity.caution,
            remedies: [
              WarningRemedy.reEnter,
              WarningRemedy.confirmAnyway,
            ],
          ));
        }
      case MeterDirection.none:
        break;
    }
  }

  void _checkDigitCount(
    Kwh candidate,
    Reading previous,
    List<ValidationWarning> warnings,
  ) {
    final candidateDigits = _wholeDigits(candidate);
    final previousDigits = _wholeDigits(previous.value);
    if (candidateDigits != previousDigits) {
      warnings.add(const ValidationWarning(
        message: "This has a different number of digits than your last "
            "reading. Check you haven't missed a digit or misread the "
            "decimal point.",
        severity: WarningSeverity.caution,
        remedies: [
          WarningRemedy.checkDecimalPoint,
          WarningRemedy.reEnter,
          WarningRemedy.confirmAnyway,
        ],
        flagIfConfirmed: ReadingFlag.digitCountMismatch,
      ));
    }
  }

  void _checkMagnitude({
    required Meter meter,
    required Kwh candidate,
    required Reading previous,
    required DateTime readAt,
    required double? rollingDailyMeanKwh,
    required bool supplyWasAvailable,
    required List<ValidationWarning> warnings,
  }) {
    final elapsed = readAt.difference(previous.readAt);
    final days = elapsed.inMinutes / (60 * 24);
    if (days <= 0) return;

    final consumed = switch (meter.direction) {
      MeterDirection.incrementing => candidate - previous.value,
      MeterDirection.decrementing => previous.value - candidate,
      MeterDirection.none => Kwh.zero,
    };

    // A negative figure here is already covered by the direction check.
    if (consumed.isNegative) return;

    final dailyRate = consumed.value / days;

    if (rollingDailyMeanKwh != null && rollingDailyMeanKwh > 0) {
      if (dailyRate > rollingDailyMeanKwh * anomalyMultiplier) {
        warnings.add(ValidationWarning(
          message: 'That works out to about ${dailyRate.toStringAsFixed(1)} '
              'kWh a day — roughly '
              '${(dailyRate / rollingDailyMeanKwh).toStringAsFixed(0)}x your '
              'usual. Worth double-checking the digits.',
          severity: WarningSeverity.caution,
          remedies: const [
            WarningRemedy.reEnter,
            WarningRemedy.confirmAnyway,
          ],
          flagIfConfirmed: ReadingFlag.anomalousHigh,
        ));
      }
    }

    if (consumed.isZero &&
        days >= zeroConsumptionDays &&
        supplyWasAvailable) {
      warnings.add(ValidationWarning(
        message: "That's no usage at all over ${days.round()} days, but you "
            'had power. Check the reading, or let us know if the property was '
            'empty.',
        severity: WarningSeverity.caution,
        remedies: const [
          WarningRemedy.reEnter,
          WarningRemedy.confirmAnyway,
        ],
        flagIfConfirmed: ReadingFlag.anomalousZero,
      ));
    }
  }

  int _wholeDigits(Kwh k) {
    final whole = (k.milli / 1000).floor().abs();
    return whole == 0 ? 1 : whole.toString().length;
  }
}
