import '../value_objects/enums.dart';
import '../value_objects/units.dart';

/// A meter reading.
///
/// **A fact.** Append-only and immutable. Corrections write a new reading
/// that supersedes this one; the original always survives. That property is
/// what makes offline merge trivial (facts union, they never conflict) and
/// what makes the dispute pack credible — a record that can be silently
/// rewritten is not evidence.
class Reading {
  const Reading({
    required this.id,
    required this.meterId,
    required this.value,
    required this.readAt,
    required this.recordedAt,
    required this.source,
    this.flags = 0,
    this.ocrConfidence,
    this.photoPath,
    this.photoSha256,
    this.supersededById,
    this.note,
  });

  final String id;
  final String meterId;

  /// The number on the meter face.
  final Kwh value;

  /// When the meter was actually read.
  final DateTime readAt;

  /// When the row was written. Differs from [readAt] for back-dated entries.
  final DateTime recordedAt;

  final ReadingSource source;
  final int flags;

  /// 0.0–1.0 for OCR readings, null for manual.
  final double? ocrConfidence;

  /// App-private path. Never a blob in the database — that would destroy
  /// query performance and backup size.
  final String? photoPath;

  /// Integrity anchor for dispute packs.
  final String? photoSha256;

  final String? supersededById;
  final String? note;

  bool get isSuperseded => supersededById != null;
  bool get hasEvidence => photoPath != null;
  bool get excludedFromBaseline => flags.excludedFromBaseline;
  Set<ReadingFlag> get flagSet => flags.flags;

  /// Whether this reading may be used in trend and baseline computation.
  bool get isClean => !isSuperseded && !excludedFromBaseline;

  Reading copyWith({
    Kwh? value,
    int? flags,
    String? supersededById,
    String? note,
  }) {
    return Reading(
      id: id,
      meterId: meterId,
      value: value ?? this.value,
      readAt: readAt,
      recordedAt: recordedAt,
      source: source,
      flags: flags ?? this.flags,
      ocrConfidence: ocrConfidence,
      photoPath: photoPath,
      photoSha256: photoSha256,
      supersededById: supersededById ?? this.supersededById,
      note: note ?? this.note,
    );
  }

  @override
  bool operator ==(Object other) => other is Reading && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A prepaid unit purchase. Also a fact.
class Purchase {
  const Purchase({
    required this.id,
    required this.meterId,
    required this.amount,
    required this.purchasedAt,
    this.units,
    this.unitsDerived = false,
    this.tokenRef,
  });

  final String id;
  final String meterId;
  final Naira amount;
  final DateTime purchasedAt;

  /// Null where the user only recorded what they paid.
  final Kwh? units;

  /// True when [units] was computed from [amount] at the configured rate
  /// rather than read off the receipt.
  final bool unitsDerived;

  final String? tokenRef;

  /// The rate actually paid. Quietly one of the most valuable figures in the
  /// product: a sustained divergence from the declared band rate is direct
  /// evidence of misclassification.
  Rate? get effectiveRate {
    final u = units;
    if (u == null || u.isZero || unitsDerived) return null;
    return Rate.fromKobo((amount.kobo * 1000 / u.milli).round());
  }

  @override
  bool operator ==(Object other) => other is Purchase && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
