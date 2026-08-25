/// A hybrid logical clock.
///
/// Device clocks in this market are frequently wrong, sometimes by days, and
/// a flat battery resets them. An HLC preserves causal ordering regardless:
/// a record created after another is always ordered after it, even when the
/// device believes otherwise.
///
/// Pure Dart, deterministic, and testable without a device.
class Hlc implements Comparable<Hlc> {
  const Hlc({
    required this.physicalMs,
    required this.counter,
    required this.nodeId,
  });

  final int physicalMs;
  final int counter;
  final String nodeId;

  static const int _maxCounter = 0xFFFF;

  factory Hlc.parse(String encoded) {
    final parts = encoded.split(':');
    if (parts.length != 3) {
      throw FormatException('Not an HLC stamp: $encoded');
    }
    return Hlc(
      physicalMs: int.parse(parts[0], radix: 16),
      counter: int.parse(parts[1], radix: 16),
      nodeId: parts[2],
    );
  }

  /// Sortable as a plain string: fixed-width hex, most significant first.
  String encode() => '${physicalMs.toRadixString(16).padLeft(12, '0')}'
      ':${counter.toRadixString(16).padLeft(4, '0')}'
      ':$nodeId';

  /// Issues the next stamp for a local event.
  ///
  /// If the wall clock has not advanced past the last stamp — because it is
  /// wrong, or because two events happened inside the same millisecond — the
  /// logical counter advances instead, so ordering is never ambiguous.
  Hlc tick(int wallClockMs) {
    if (wallClockMs > physicalMs) {
      return Hlc(physicalMs: wallClockMs, counter: 0, nodeId: nodeId);
    }
    if (counter >= _maxCounter) {
      return Hlc(physicalMs: physicalMs + 1, counter: 0, nodeId: nodeId);
    }
    return Hlc(
      physicalMs: physicalMs,
      counter: counter + 1,
      nodeId: nodeId,
    );
  }

  /// Merges a stamp received from another node, per the standard HLC rule.
  Hlc merge(Hlc remote, int wallClockMs) {
    final maxPhysical = [physicalMs, remote.physicalMs, wallClockMs]
        .reduce((a, b) => a > b ? a : b);

    if (maxPhysical == physicalMs && maxPhysical == remote.physicalMs) {
      return Hlc(
        physicalMs: maxPhysical,
        counter: (counter > remote.counter ? counter : remote.counter) + 1,
        nodeId: nodeId,
      );
    }
    if (maxPhysical == physicalMs) {
      return Hlc(
        physicalMs: maxPhysical,
        counter: counter + 1,
        nodeId: nodeId,
      );
    }
    if (maxPhysical == remote.physicalMs) {
      return Hlc(
        physicalMs: maxPhysical,
        counter: remote.counter + 1,
        nodeId: nodeId,
      );
    }
    return Hlc(physicalMs: maxPhysical, counter: 0, nodeId: nodeId);
  }

  /// Whether this stamp causally dominates [other]. Used to resolve
  /// last-writer-wins on mutable records.
  bool dominates(Hlc other) => compareTo(other) > 0;

  @override
  int compareTo(Hlc other) {
    final byPhysical = physicalMs.compareTo(other.physicalMs);
    if (byPhysical != 0) return byPhysical;
    final byCounter = counter.compareTo(other.counter);
    if (byCounter != 0) return byCounter;
    // Node id breaks ties deterministically, so every device resolves a
    // simultaneous write the same way.
    return nodeId.compareTo(other.nodeId);
  }

  @override
  bool operator ==(Object other) =>
      other is Hlc &&
      other.physicalMs == physicalMs &&
      other.counter == counter &&
      other.nodeId == nodeId;

  @override
  int get hashCode => Object.hash(physicalMs, counter, nodeId);

  @override
  String toString() => encode();
}

/// Issues monotonically increasing stamps for this device.
class HlcClock {
  HlcClock({required String nodeId, Hlc? initial})
      : _current = initial ??
            Hlc(physicalMs: 0, counter: 0, nodeId: nodeId);

  Hlc _current;

  Hlc get current => _current;

  /// Stamps a local event. [wallClockMs] is injected rather than read from
  /// DateTime.now() so this is deterministic under test.
  Hlc issue(int wallClockMs) {
    _current = _current.tick(wallClockMs);
    return _current;
  }

  Hlc receive(Hlc remote, int wallClockMs) {
    _current = _current.merge(remote, wallClockMs);
    return _current;
  }
}
