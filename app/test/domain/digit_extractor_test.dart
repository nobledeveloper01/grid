import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/digit_extractor.dart';
import 'package:grid/domain/value_objects/enums.dart';

void main() {
  const extractor = DigitExtractor();

  TextBlock block(
    String text, {
    double confidence = 0.95,
    double left = 0.3,
    double top = 0.4,
    double width = 0.4,
    double height = 0.2,
  }) =>
      TextBlock(
        text: text,
        confidence: confidence,
        left: left,
        top: top,
        width: width,
        height: height,
      );

  /// A realistic meter face: a large centred register, a small serial number
  /// at the top, a model number at the bottom, and a certification mark.
  List<TextBlock> meterFace({String register = '045821'}) => [
        block('SERIAL 6210457733',
            confidence: 0.92, left: 0.05, top: 0.06, width: 0.5, height: 0.05),
        block(register,
            confidence: 0.94, left: 0.28, top: 0.42, width: 0.44, height: 0.20),
        block('kWh', confidence: 0.9, left: 0.74, top: 0.46, width: 0.1, height: 0.06),
        block('MODEL DDS-1234',
            confidence: 0.88, left: 0.1, top: 0.88, width: 0.45, height: 0.05),
      ];

  group('nothing to extract', () {
    test('returns null on an empty result', () {
      expect(extractor.extract(blocks: const []), isNull);
    });

    test('returns null when nothing looks like a register', () {
      final result = extractor.extract(blocks: [
        block('kWh', left: 0.1, top: 0.1, width: 0.1, height: 0.05),
        block('IBEDC', left: 0.4, top: 0.1, width: 0.2, height: 0.05),
      ]);
      expect(result, isNull);
    });

    test('rejects digit runs that are too short or too long', () {
      expect(extractor.extract(blocks: [block('42')]), isNull);
      expect(extractor.extract(blocks: [block('1234567890123')]), isNull);
    });
  });

  group('choosing the register', () {
    test('picks the large centred number over the serial number', () {
      final result = extractor.extract(blocks: meterFace())!;
      expect(result.digits, '045821');
      expect(result.value, 45821);
    });

    test('ignores a serial number even when it is longer and more confident', () {
      final result = extractor.extract(blocks: [
        block('9988776655',
            confidence: 1.0, left: 0.05, top: 0.05, width: 0.6, height: 0.05),
        block('01234',
            confidence: 0.7, left: 0.3, top: 0.45, width: 0.4, height: 0.22),
      ])!;
      expect(result.digits, '01234');
    });

    test('strips the separators a meter face actually uses', () {
      final result = extractor.extract(blocks: [
        block('04582.1', left: 0.28, top: 0.42, width: 0.44, height: 0.2),
      ])!;
      expect(result.digits, '045821');
    });

    test('reports how many candidates it weighed', () {
      final result = extractor.extract(blocks: meterFace())!;
      expect(result.candidatesConsidered, greaterThanOrEqualTo(1));
    });

    test('keeps the full recognised text for the record', () {
      final result = extractor.extract(blocks: meterFace())!;
      expect(result.rawText, contains('SERIAL'));
      expect(result.rawText, contains('045821'));
    });
  });

  group('the expected digit count', () {
    test('breaks a tie in favour of the right length', () {
      // Two equally-placed candidates; only the digit count separates them.
      final blocks = [
        block('12345', left: 0.28, top: 0.40, width: 0.44, height: 0.20),
        block('123456', left: 0.28, top: 0.44, width: 0.44, height: 0.20),
      ];
      expect(
        extractor.extract(blocks: blocks, expectedDigitCount: 5)!.digits,
        '12345',
      );
      expect(
        extractor.extract(blocks: blocks, expectedDigitCount: 6)!.digits,
        '123456',
      );
    });

    test('still returns something when no candidate matches the hint', () {
      final result = extractor.extract(
        blocks: meterFace(),
        expectedDigitCount: 8,
      );
      expect(result, isNotNull, reason: 'a poor match beats no answer at all');
      expect(result!.digits, '045821');
    });
  });

  group('confidence', () {
    test('a clean centred register is usable', () {
      final result = extractor.extract(blocks: meterFace())!;
      expect(result.isUsable, isTrue);
      expect(result.confidence, greaterThan(0.6));
    });

    test('falls below the manual-entry threshold when the recogniser is unsure', () {
      final result = extractor.extract(blocks: [
        block('045821',
            confidence: 0.25, left: 0.28, top: 0.42, width: 0.44, height: 0.20),
      ])!;
      expect(result.isUsable, isFalse);
      expect(
        result.confidence,
        lessThan(ExtractedReading.manualFallbackThreshold),
      );
    });

    test('an off-centre candidate scores lower than a centred one', () {
      final centred = extractor.extract(blocks: [
        block('045821', left: 0.28, top: 0.42, width: 0.44, height: 0.2),
      ])!;
      final edge = extractor.extract(blocks: [
        block('045821', left: 0.02, top: 0.02, width: 0.44, height: 0.2),
      ])!;
      expect(centred.confidence, greaterThan(edge.confidence));
    });

    test('never reports a confidence outside 0..1', () {
      for (final c in [0.0, 0.5, 1.0]) {
        final r = extractor.extract(blocks: [
          block('045821', confidence: c, left: 0.28, top: 0.42, width: 0.44, height: 0.2),
        ])!;
        expect(r.confidence, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('uncertain characters', () {
    test('marks none when confidence is high', () {
      final result = extractor.extract(blocks: meterFace())!;
      expect(result.uncertainPositions, isEmpty);
    });

    test('marks the easily-confused digits when confidence is middling', () {
      final result = extractor.extract(blocks: [
        block('086921',
            confidence: 0.62, left: 0.28, top: 0.42, width: 0.44, height: 0.2),
      ])!;
      expect(result.uncertainPositions, isNotEmpty);
      // 0, 8, 6, 9 and 1 are the ones that misread on a mechanical register.
      expect(result.uncertainPositions, contains(0));
      for (final i in result.uncertainPositions) {
        expect('086921'[i], isNot('2'),
            reason: 'digits that do not confuse should not be flagged');
      }
    });

    test('positions are valid indices into the digits', () {
      final result = extractor.extract(blocks: [
        block('086921',
            confidence: 0.62, left: 0.28, top: 0.42, width: 0.44, height: 0.2),
      ])!;
      for (final i in result.uncertainPositions) {
        expect(i, inInclusiveRange(0, result.digits.length - 1));
      }
    });
  });

  group('determinism', () {
    test('the same input always yields the same answer', () {
      final blocks = meterFace();
      final first = extractor.extract(blocks: blocks, meterType: MeterType.postpaidDigital);
      for (var i = 0; i < 20; i++) {
        final again = extractor.extract(
          blocks: blocks,
          meterType: MeterType.postpaidDigital,
        );
        expect(again!.digits, first!.digits);
        expect(again.confidence, first.confidence);
      }
    });

    test('block order does not change the answer', () {
      final forward = extractor.extract(blocks: meterFace())!;
      final reversed = extractor.extract(blocks: meterFace().reversed.toList())!;
      expect(reversed.digits, forward.digits);
    });
  });
}
