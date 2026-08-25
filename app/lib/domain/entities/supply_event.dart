import '../value_objects/enums.dart';

/// A period during which the grid was in a given state.
///
/// A fact: append-only. A manual entry supersedes an inferred one for an
/// overlapping period rather than editing it, so the original inference
/// remains auditable.
class SupplyEvent {
  const SupplyEvent({
    required this.id,
    required this.meterId,
    required this.state,
    required this.startedAt,
    required this.source,
    required this.platformCapability,
    this.endedAt,
    this.note,
    this.supersededById,
  });

  final String id;
  final String meterId;
  final SupplyState state;
  final DateTime startedAt;

  /// Null while ongoing.
  final DateTime? endedAt;

  final SupplySource source;

  /// What the platform could promise when this was recorded. See
  /// [PlatformCapability] — this is why coverage can be reported honestly
  /// across a period where the device's capability changed.
  final PlatformCapability platformCapability;

  final String? note;
  final String? supersededById;

  bool get isOngoing => endedAt == null;
  bool get isInferred => source == SupplySource.inferredCharging;
  bool get isSuperseded => supersededById != null;

  Duration durationAt(DateTime now) =>
      (endedAt ?? now).difference(startedAt);

  /// Overlap between this event and an arbitrary window, in minutes.
  /// Returns zero where they do not intersect.
  int overlapMinutes(DateTime windowStart, DateTime windowEnd, DateTime now) {
    final end = endedAt ?? now;
    final from = startedAt.isAfter(windowStart) ? startedAt : windowStart;
    final to = end.isBefore(windowEnd) ? end : windowEnd;
    if (!to.isAfter(from)) return 0;
    return to.difference(from).inMinutes;
  }

  @override
  bool operator ==(Object other) => other is SupplyEvent && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
