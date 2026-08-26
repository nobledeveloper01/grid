import '../services/escalation_engine.dart';

/// A complaint in progress.
///
/// State rather than a fact: it moves, and the user is entitled to correct
/// their own account of where it has got to. The readings and supply events
/// underneath it are what cannot be rewritten.
class DisputeCase {
  const DisputeCase({
    required this.id,
    required this.meterId,
    required this.kind,
    required this.step,
    required this.status,
    required this.periodStart,
    required this.periodEnd,
    required this.createdAt,
    this.submittedAt,
    this.reference,
    this.notes,
    this.packPath,
  });

  final String id;
  final String meterId;

  /// `PackKind.name`, kept as a string so the entity does not have to move
  /// every time a template is added.
  final String kind;

  final EscalationStep step;
  final CaseStatus status;
  final DateTime periodStart;
  final DateTime periodEnd;
  final DateTime createdAt;

  final DateTime? submittedAt;

  /// The DisCo's own reference. The single most useful thing to have written
  /// down before the next step.
  final String? reference;

  final String? notes;
  final String? packPath;

  bool get isClosed =>
      status == CaseStatus.resolved || status == CaseStatus.abandoned;

  DisputeCase copyWith({
    EscalationStep? step,
    CaseStatus? status,
    DateTime? submittedAt,
    String? reference,
    String? notes,
    String? packPath,
    bool clearSubmittedAt = false,
  }) =>
      DisputeCase(
        id: id,
        meterId: meterId,
        kind: kind,
        step: step ?? this.step,
        status: status ?? this.status,
        periodStart: periodStart,
        periodEnd: periodEnd,
        createdAt: createdAt,
        submittedAt: clearSubmittedAt ? null : (submittedAt ?? this.submittedAt),
        reference: reference ?? this.reference,
        notes: notes ?? this.notes,
        packPath: packPath ?? this.packPath,
      );

  @override
  bool operator ==(Object other) => other is DisputeCase && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
