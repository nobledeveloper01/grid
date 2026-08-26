import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/services/digit_extractor.dart';
import '../../domain/value_objects/enums.dart';

/// On-device text recognition.
///
/// **Why this is a façade and not a package dependency.** Google's ML Kit iOS
/// pods ship no arm64 simulator slice, so a direct dependency makes the app
/// un-installable on an Apple Silicon simulator — which is every current Mac.
/// See ADR-0004.
///
/// The engine is therefore chosen per platform behind this interface: ML Kit
/// on Android, Apple's Vision framework on iOS. Both are better than the
/// cross-platform package, and neither can hold simulator development hostage.
abstract interface class TextRecogniser {
  /// Whether recognition works on this device and platform. The capture UI
  /// hides the camera path entirely when it does not, rather than offering a
  /// button that fails.
  Future<bool> get isAvailable;

  /// Extracts the most likely meter-register digit run from an image.
  ///
  /// Returns null when nothing usable was found. Completes within [budget] or
  /// abandons — under no circumstance does the user wait on a spinner at a
  /// meter at night (FR-2.2).
  Future<ExtractedReading?> readDigits(
    String imagePath, {
    MeterType? meterType,
    int? expectedDigitCount,
    Duration budget = const Duration(milliseconds: 1500),
  });
}

/// Talks to the native recogniser over a method channel, then hands the raw
/// blocks to the pure-Dart [DigitExtractor] to choose the register.
///
/// The split matters: the native side does recognition and nothing else, so
/// the selection logic — the part with the judgement in it — stays testable
/// without a device and identical on both platforms.
class PlatformTextRecogniser implements TextRecogniser {
  const PlatformTextRecogniser({
    this.channel = const MethodChannel('grid/text_recogniser'),
    this.extractor = const DigitExtractor(),
  });

  final MethodChannel channel;
  final DigitExtractor extractor;

  @override
  Future<bool> get isAvailable async {
    try {
      final available = await channel.invokeMethod<bool>('isAvailable');
      return available ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // No native side registered — a legitimate state, not an error.
      return false;
    }
  }

  @override
  Future<ExtractedReading?> readDigits(
    String imagePath, {
    MeterType? meterType,
    int? expectedDigitCount,
    Duration budget = const Duration(milliseconds: 1500),
  }) async {
    try {
      final raw = await channel.invokeMethod<List<dynamic>>(
        'recognise',
        {'path': imagePath},
      ).timeout(budget);

      if (raw == null || raw.isEmpty) return null;

      final blocks = <TextBlock>[];
      for (final entry in raw) {
        final map = (entry as Map).cast<String, dynamic>();
        blocks.add(
          TextBlock(
            text: map['text'] as String? ?? '',
            confidence: (map['confidence'] as num?)?.toDouble() ?? 1.0,
            left: (map['left'] as num?)?.toDouble() ?? 0,
            top: (map['top'] as num?)?.toDouble() ?? 0,
            width: (map['width'] as num?)?.toDouble() ?? 0,
            height: (map['height'] as num?)?.toDouble() ?? 0,
          ),
        );
      }

      return extractor.extract(
        blocks: blocks,
        meterType: meterType,
        expectedDigitCount: expectedDigitCount,
      );
    } on TimeoutException {
      // Budget blown. Abandon rather than keep the user waiting; the capture
      // flow drops to manual entry with the photograph already taken.
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}

/// Used where no engine is wired up.
///
/// Reports itself unavailable rather than pretending to work, so the UI routes
/// straight to manual entry instead of offering a camera path that would fail.
class NullTextRecogniser implements TextRecogniser {
  const NullTextRecogniser();

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<ExtractedReading?> readDigits(
    String imagePath, {
    MeterType? meterType,
    int? expectedDigitCount,
    Duration budget = const Duration(milliseconds: 1500),
  }) async =>
      null;
}
