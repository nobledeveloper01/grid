import '../value_objects/enums.dart';

/// A block of text found in an image, with where it sits and how sure the
/// recogniser was.
///
/// Pure data. The platform recogniser produces these; nothing here knows
/// whether they came from ML Kit, Vision, or a test fixture.
class TextBlock {
  const TextBlock({
    required this.text,
    required this.confidence,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;

  /// 0.0–1.0. Some recognisers do not report per-block confidence; they
  /// pass 1.0 and the extractor leans on geometry instead.
  final double confidence;

  /// Bounding box, normalised to 0–1 against the source image.
  final double left;
  final double top;
  final double width;
  final double height;

  double get right => left + width;
  double get bottom => top + height;
  double get centreX => left + width / 2;
  double get centreY => top + height / 2;
  double get area => width * height;

  /// Digits only, with the separators a meter face actually uses stripped.
  String get digitsOnly => text.replaceAll(RegExp(r'[^0-9]'), '');
}

/// A digit run selected from the image, with the reasoning that picked it.
class ExtractedReading {
  const ExtractedReading({
    required this.digits,
    required this.confidence,
    required this.uncertainPositions,
    required this.rawText,
    required this.candidatesConsidered,
  });

  final String digits;

  /// Combined confidence: the recogniser's own, adjusted for how well the
  /// candidate matched the expected register geometry.
  final double confidence;

  /// Indices into [digits] the UI should mark as uncertain, so the user
  /// checks those characters rather than re-reading the whole number.
  final Set<int> uncertainPositions;

  final String rawText;
  final int candidatesConsidered;

  /// Below this, the caller falls back to manual entry rather than
  /// pre-filling something misleading.
  static const double manualFallbackThreshold = 0.60;

  /// Below this, an individual character is marked uncertain in the UI.
  static const double uncertainCharacterThreshold = 0.80;

  bool get isUsable => confidence >= manualFallbackThreshold;

  double? get value => double.tryParse(digits);
}

/// Selects the meter register from everything the recogniser found.
///
/// A meter face carries far more text than the reading: a serial number, a
/// model number, certification marks, a utility logo, sometimes a barcode.
/// Handing the raw recognised text to the user would be worse than useless,
/// so the register has to be *chosen*.
///
/// Pure Dart. Deterministic for a given (blocks, meter type, expected digit
/// count), which is what makes it testable without a camera.
class DigitExtractor {
  const DigitExtractor();

  /// Register digits are large. A candidate shorter than this fraction of
  /// the tallest text found is almost certainly a serial number.
  static const double _minRelativeHeight = 0.55;

  /// Plausible register lengths when the meter type does not tell us.
  static const int _minDigits = 3;
  static const int _maxDigits = 9;

  ExtractedReading? extract({
    required List<TextBlock> blocks,
    MeterType? meterType,
    int? expectedDigitCount,
  }) {
    if (blocks.isEmpty) return null;

    final tallest = blocks
        .map((b) => b.height)
        .fold<double>(0, (a, h) => h > a ? h : a);

    final candidates = <_Candidate>[];

    for (final block in blocks) {
      final digits = block.digitsOnly;
      if (digits.length < _minDigits || digits.length > _maxDigits) continue;

      // A register is one of the largest things on the face. A serial number
      // printed small alongside it is the commonest wrong answer.
      final relativeHeight = tallest == 0 ? 0.0 : block.height / tallest;
      if (relativeHeight < _minRelativeHeight) continue;

      candidates.add(
        _Candidate(
          block: block,
          digits: digits,
          score: _score(
            block: block,
            digits: digits,
            relativeHeight: relativeHeight,
            expectedDigitCount: expectedDigitCount,
          ),
        ),
      );
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.score.compareTo(a.score));
    final best = candidates.first;

    // The score already folds in geometry; the reported confidence blends it
    // with what the recogniser itself claimed, so a confident recogniser on a
    // badly-placed candidate still reads as uncertain.
    final confidence = (best.block.confidence * 0.6) + (best.score * 0.4);

    return ExtractedReading(
      digits: best.digits,
      confidence: confidence.clamp(0.0, 1.0),
      uncertainPositions: _uncertainPositions(best, confidence),
      rawText: blocks.map((b) => b.text).join(' '),
      candidatesConsidered: candidates.length,
    );
  }

  /// How well a candidate looks like a meter register, 0–1.
  double _score({
    required TextBlock block,
    required String digits,
    required double relativeHeight,
    required int? expectedDigitCount,
  }) {
    var score = 0.0;

    // Size relative to everything else on the face.
    score += relativeHeight * 0.35;

    // Digit count against what this meter type should show. When we know it,
    // it is the strongest single signal available.
    if (expectedDigitCount != null) {
      final delta = (digits.length - expectedDigitCount).abs();
      score += switch (delta) {
        0 => 0.35,
        1 => 0.18,
        2 => 0.05,
        _ => 0.0,
      };
    } else {
      // Without a hint, 5–6 digits is the commonest register length.
      score += switch (digits.length) {
        5 || 6 => 0.22,
        4 || 7 => 0.16,
        _ => 0.08,
      };
    }

    // Registers sit in the middle band of the face, horizontally centred.
    // Serial numbers cluster at the top and bottom edges.
    final verticalCentrality = 1.0 - (block.centreY - 0.5).abs() * 2;
    score += verticalCentrality.clamp(0.0, 1.0) * 0.18;

    final horizontalCentrality = 1.0 - (block.centreX - 0.5).abs() * 2;
    score += horizontalCentrality.clamp(0.0, 1.0) * 0.12;

    return score.clamp(0.0, 1.0);
  }

  /// Which characters to flag for the user to check.
  ///
  /// A recogniser reporting low confidence overall gives no per-character
  /// detail, so we mark the characters most often misread on a seven-segment
  /// or mechanical display: 8/0/6/9 confuse with each other, and 1/7 do.
  Set<int> _uncertainPositions(_Candidate candidate, double confidence) {
    if (confidence >= ExtractedReading.uncertainCharacterThreshold) {
      return const {};
    }
    const ambiguous = {'0', '6', '8', '9', '1', '7', '5', '3'};
    final positions = <int>{};
    for (var i = 0; i < candidate.digits.length; i++) {
      if (ambiguous.contains(candidate.digits[i])) positions.add(i);
    }
    return positions;
  }
}

class _Candidate {
  const _Candidate({
    required this.block,
    required this.digits,
    required this.score,
  });

  final TextBlock block;
  final String digits;
  final double score;
}
