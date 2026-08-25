/// On-device text recognition.
///
/// Declared as a façade with a null implementation so nothing in the app
/// depends on a specific OCR engine.
///
/// **Why this is a façade and not a direct dependency.** Google's ML Kit iOS
/// pods ship no arm64 simulator slice, so taking a direct dependency makes
/// the whole app un-installable on an Apple Silicon simulator — which is
/// every current Mac. Isolating it here means OCR can be:
///
///   * ML Kit on Android,
///   * Apple's Vision framework via a platform channel on iOS,
///   * or absent, with manual entry carrying the flow.
///
/// FR-2.2 already requires that OCR never blocks: a failure falls through to
/// manual entry without being framed as an error. [NullTextRecogniser] is
/// simply that fallback made explicit, and it keeps the app honest on a
/// platform where recognition genuinely is not available.
library;

/// One digit run found in an image, with per-character confidence.
class RecognisedDigits {
  const RecognisedDigits({
    required this.digits,
    required this.confidence,
    this.rawText,
  });

  final String digits;

  /// 0.0–1.0. Below 0.60 the caller must fall back to manual entry; below
  /// 0.80 individual characters are marked uncertain in the UI.
  final double confidence;

  final String? rawText;

  static const double manualFallbackThreshold = 0.60;
  static const double uncertainCharacterThreshold = 0.80;

  bool get isUsable => confidence >= manualFallbackThreshold;
}

abstract interface class TextRecogniser {
  /// Whether recognition is available at all on this device and platform.
  /// The capture UI hides the camera path entirely when it is not.
  Future<bool> get isAvailable;

  /// Extracts the most likely meter-register digit run from an image.
  ///
  /// Returns null when nothing usable was found. Must complete within
  /// [budget] or abandon — under no circumstance does the user wait on a
  /// spinner at a meter at night (FR-2.2).
  Future<RecognisedDigits?> readDigits(
    String imagePath, {
    int? expectedDigitCount,
    Duration budget = const Duration(milliseconds: 1500),
  });
}

/// The no-op implementation used where no engine is wired up.
///
/// Reports itself unavailable rather than pretending to work, so the UI
/// routes straight to manual entry instead of offering a camera path that
/// would fail.
class NullTextRecogniser implements TextRecogniser {
  const NullTextRecogniser();

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<RecognisedDigits?> readDigits(
    String imagePath, {
    int? expectedDigitCount,
    Duration budget = const Duration(milliseconds: 1500),
  }) async =>
      null;
}
