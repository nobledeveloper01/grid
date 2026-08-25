import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/validation_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  const engine = ValidationEngine();

  group('empty history', () {
    test('accepts any first reading without warnings', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(1234),
        readAt: now,
        history: const [],
      );
      expect(outcome.isClean, isTrue);
      expect(outcome.isBlocked, isFalse);
    });
  });

  group('ordering', () {
    test('rejects a reading dated before the previous one', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(1300),
        readAt: now.subtract(const Duration(days: 2)),
        history: [reading(id: 'r1', value: 1200, at: now)],
      );
      expect(outcome.isBlocked, isTrue);
      expect(outcome.warnings.single.remedies, [WarningRemedy.reject]);
    });

    test('rejection is the only blocking outcome in the engine', () {
      // Every other rule must offer a way forward. A dead end at a meter at
      // night costs the reading and possibly the user.
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(500),
        readAt: now,
        history: [reading(id: 'r1', value: 1200, at: now.subtract(const Duration(days: 1)))],
      );
      expect(outcome.isBlocked, isFalse);
      expect(
        outcome.warnings.every((w) => w.remedies.contains(WarningRemedy.confirmAnyway)),
        isTrue,
      );
    });
  });

  group('direction', () {
    test('warns when a postpaid reading goes backwards', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(900),
        readAt: now,
        history: [reading(id: 'r1', value: 1200, at: now.subtract(const Duration(days: 1)))],
      );
      expect(outcome.isClean, isFalse);
      expect(
        outcome.warnings.first.remedies,
        contains(WarningRemedy.meterWasReplaced),
      );
      expect(
        outcome.flagsIfConfirmed.has(ReadingFlag.rolloverOrReplacement),
        isTrue,
      );
    });

    test('warns when a prepaid reading goes up', () {
      final outcome = engine.validate(
        meter: meter(type: MeterType.prepaidKeypad),
        candidate: Kwh.fromDouble(150),
        readAt: now,
        history: [reading(id: 'r1', value: 80, at: now.subtract(const Duration(days: 1)))],
      );
      expect(outcome.isClean, isFalse);
      expect(outcome.warnings.first.severity, WarningSeverity.caution);
      expect(outcome.warnings.first.remedies, contains(WarningRemedy.reEnter));
    });

    test('accepts a normal prepaid decrement', () {
      final outcome = engine.validate(
        meter: meter(type: MeterType.prepaidKeypad),
        candidate: Kwh.fromDouble(70),
        readAt: now,
        history: [reading(id: 'r1', value: 80, at: now.subtract(const Duration(days: 1)))],
      );
      expect(outcome.isClean, isTrue);
    });
  });

  group('duplicates', () {
    test('flags an identical repeat inside the window but does not warn hard', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(1200),
        readAt: now,
        history: [reading(id: 'r1', value: 1200, at: now.subtract(const Duration(hours: 2)))],
      );
      expect(outcome.warnings.single.severity, WarningSeverity.info);
      expect(outcome.flagsIfConfirmed.has(ReadingFlag.duplicateWindow), isTrue);
    });

    test('an identical reading outside the window is a real zero-usage case', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(1200),
        readAt: now,
        history: [reading(id: 'r1', value: 1200, at: now.subtract(const Duration(days: 5)))],
      );
      expect(outcome.flagsIfConfirmed.has(ReadingFlag.duplicateWindow), isFalse);
      expect(outcome.flagsIfConfirmed.has(ReadingFlag.anomalousZero), isTrue);
    });
  });

  group('magnitude', () {
    test('flags consumption far above the rolling mean', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(1300),
        readAt: now,
        history: [reading(id: 'r1', value: 1200, at: now.subtract(const Duration(days: 1)))],
        rollingDailyMeanKwh: 10,
      );
      expect(outcome.flagsIfConfirmed.has(ReadingFlag.anomalousHigh), isTrue);
    });

    test('does not flag consumption within the normal band', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(1212),
        readAt: now,
        history: [reading(id: 'r1', value: 1200, at: now.subtract(const Duration(days: 1)))],
        rollingDailyMeanKwh: 10,
      );
      expect(outcome.flagsIfConfirmed.has(ReadingFlag.anomalousHigh), isFalse);
    });

    test('does not flag zero usage when there was no power', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(1200),
        readAt: now,
        history: [reading(id: 'r1', value: 1200, at: now.subtract(const Duration(days: 5)))],
        supplyWasAvailable: false,
      );
      expect(outcome.flagsIfConfirmed.has(ReadingFlag.anomalousZero), isFalse);
    });
  });

  group('digit count', () {
    test('flags a dropped leading digit', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(234),
        readAt: now,
        history: [reading(id: 'r1', value: 1200, at: now.subtract(const Duration(days: 1)))],
      );
      expect(
        outcome.flagsIfConfirmed.has(ReadingFlag.digitCountMismatch),
        isTrue,
      );
    });
  });

  group('superseded readings', () {
    test('are ignored when picking the previous reading', () {
      final outcome = engine.validate(
        meter: meter(),
        candidate: Kwh.fromDouble(1250),
        readAt: now,
        history: [
          reading(
            id: 'bad',
            value: 9999,
            at: now.subtract(const Duration(hours: 1)),
            supersededById: 'good',
          ),
          reading(id: 'good', value: 1240, at: now.subtract(const Duration(days: 1))),
        ],
      );
      expect(outcome.isClean, isTrue);
    });
  });
}
