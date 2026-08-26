import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:grid/core/platform/text_recogniser.dart';
import 'package:grid/domain/value_objects/enums.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('grid/text_recogniser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  /// Stands in for the native side.
  void mockNative(Future<Object?> Function(MethodCall call) handler) {
    messenger.setMockMethodCallHandler(channel, handler);
  }

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  Map<String, Object?> block(
    String text, {
    double confidence = 0.95,
    double left = 0.28,
    double top = 0.42,
    double width = 0.44,
    double height = 0.2,
  }) =>
      {
        'text': text,
        'confidence': confidence,
        'left': left,
        'top': top,
        'width': width,
        'height': height,
      };

  group('availability', () {
    test('reports what the platform reports', () async {
      mockNative((call) async => call.method == 'isAvailable' ? true : null);
      expect(await const PlatformTextRecogniser().isAvailable, isTrue);
    });

    test('is false when no native side is registered', () async {
      // No mock handler: the channel raises MissingPluginException, which is a
      // legitimate state (no engine wired up), not an error.
      expect(await const PlatformTextRecogniser().isAvailable, isFalse);
    });

    test('is false when the platform throws', () async {
      mockNative((call) async => throw PlatformException(code: 'boom'));
      expect(await const PlatformTextRecogniser().isAvailable, isFalse);
    });

    test('is false when the platform returns null', () async {
      mockNative((call) async => null);
      expect(await const PlatformTextRecogniser().isAvailable, isFalse);
    });
  });

  group('reading digits', () {
    test('picks the register out of a full meter face', () async {
      mockNative((call) async => [
            block('SERIAL 6210457733',
                left: 0.05, top: 0.06, width: 0.5, height: 0.05),
            block('045821'),
            block('kWh', left: 0.74, top: 0.46, width: 0.1, height: 0.06),
          ]);

      final reading = await const PlatformTextRecogniser().readDigits(
        '/tmp/meter.jpg',
        meterType: MeterType.postpaidDigital,
      );

      expect(reading, isNotNull);
      expect(reading!.digits, '045821');
      expect(reading.isUsable, isTrue);
    });

    test('returns null when the platform finds nothing', () async {
      mockNative((call) async => <dynamic>[]);
      expect(
        await const PlatformTextRecogniser().readDigits('/tmp/meter.jpg'),
        isNull,
      );
    });

    test('returns null rather than throwing when the platform errors', () async {
      mockNative((call) async => throw PlatformException(code: 'unreadable'));
      expect(
        await const PlatformTextRecogniser().readDigits('/tmp/meter.jpg'),
        isNull,
      );
    });

    test('returns null when no native side is registered', () async {
      expect(
        await const PlatformTextRecogniser().readDigits('/tmp/meter.jpg'),
        isNull,
      );
    });

    test('survives a malformed payload from the platform', () async {
      // A native side that omits fields must not crash the capture flow.
      mockNative((call) async => [
            {'text': '045821'},
            {'confidence': 0.9},
            <String, Object?>{},
          ]);
      final reading =
          await const PlatformTextRecogniser().readDigits('/tmp/meter.jpg');
      // Zero-height blocks cannot score as a register. The point of the test
      // is that nothing threw.
      expect(reading, isNull);
    });

    test('passes the expected digit count through to the extractor', () async {
      mockNative((call) async => [
            block('12345', top: 0.40),
            block('123456', top: 0.44),
          ]);
      final five = await const PlatformTextRecogniser()
          .readDigits('/tmp/m.jpg', expectedDigitCount: 5);
      final six = await const PlatformTextRecogniser()
          .readDigits('/tmp/m.jpg', expectedDigitCount: 6);
      expect(five!.digits, '12345');
      expect(six!.digits, '123456');
    });
  });

  group('the time budget', () {
    test('abandons rather than keeping the user waiting', () async {
      // FR-2.2: under no circumstance does the user wait on a spinner at a
      // meter at night. A slow platform is abandoned, not awaited.
      mockNative((call) async {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        return [block('045821')];
      });

      final watch = Stopwatch()..start();
      final reading = await const PlatformTextRecogniser().readDigits(
        '/tmp/meter.jpg',
        budget: const Duration(milliseconds: 60),
      );
      watch.stop();

      expect(reading, isNull, reason: 'the budget was blown, so give up');
      expect(
        watch.elapsedMilliseconds,
        lessThan(350),
        reason: 'and give up promptly, rather than waiting it out',
      );
    });

    test('returns normally when the platform beats the budget', () async {
      mockNative((call) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return [block('045821')];
      });
      final reading = await const PlatformTextRecogniser().readDigits(
        '/tmp/meter.jpg',
        budget: const Duration(milliseconds: 500),
      );
      expect(reading!.digits, '045821');
    });
  });

  group('NullTextRecogniser', () {
    test('reports itself unavailable rather than pretending', () async {
      expect(await const NullTextRecogniser().isAvailable, isFalse);
    });

    test('never returns a reading', () async {
      expect(
        await const NullTextRecogniser().readDigits('/tmp/anything.jpg'),
        isNull,
      );
    });
  });
}
