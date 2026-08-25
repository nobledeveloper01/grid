import 'package:flutter_test/flutter_test.dart';
import 'package:grid/data/local/hlc.dart';

void main() {
  group('encoding', () {
    test('round-trips', () {
      const h = Hlc(physicalMs: 1756123456789, counter: 42, nodeId: 'abc123');
      expect(Hlc.parse(h.encode()), h);
    });

    test('encodes to a lexicographically sortable string', () {
      final clock = HlcClock(nodeId: 'n1');
      final stamps = [
        clock.issue(1000).encode(),
        clock.issue(2000).encode(),
        clock.issue(3000).encode(),
      ];
      final sorted = [...stamps]..sort();
      expect(sorted, stamps);
    });

    test('rejects malformed input', () {
      expect(() => Hlc.parse('nonsense'), throwsFormatException);
    });
  });

  group('ordering under a well-behaved clock', () {
    test('advances with wall time', () {
      final clock = HlcClock(nodeId: 'n1');
      final a = clock.issue(1000);
      final b = clock.issue(2000);
      expect(b.dominates(a), isTrue);
      expect(b.counter, 0);
    });
  });

  group('ordering under a broken clock', () {
    test('keeps ordering when the wall clock stands still', () {
      final clock = HlcClock(nodeId: 'n1');
      final a = clock.issue(1000);
      final b = clock.issue(1000);
      final c = clock.issue(1000);
      expect(b.dominates(a), isTrue);
      expect(c.dominates(b), isTrue);
      expect(c.counter, 2);
    });

    test('keeps ordering when the wall clock jumps backwards', () {
      // The device was powered off and came back believing it is 1970.
      final clock = HlcClock(nodeId: 'n1');
      final a = clock.issue(1756123456789);
      final b = clock.issue(0);
      expect(
        b.dominates(a),
        isTrue,
        reason: 'a later event must still order after an earlier one',
      );
    });

    test('does not lose ordering across a counter overflow', () {
      var stamp = const Hlc(physicalMs: 1000, counter: 0xFFFF, nodeId: 'n1');
      final next = stamp.tick(1000);
      expect(next.dominates(stamp), isTrue);
      expect(next.physicalMs, 1001);
      expect(next.counter, 0);
    });
  });

  group('merge', () {
    test('dominates both sides', () {
      const local = Hlc(physicalMs: 1000, counter: 5, nodeId: 'a');
      const remote = Hlc(physicalMs: 1000, counter: 9, nodeId: 'b');
      final merged = local.merge(remote, 1000);
      expect(merged.dominates(local), isTrue);
      expect(merged.dominates(remote), isTrue);
    });

    test('adopts a remote stamp from the future', () {
      const local = Hlc(physicalMs: 1000, counter: 0, nodeId: 'a');
      const remote = Hlc(physicalMs: 5000, counter: 3, nodeId: 'b');
      final merged = local.merge(remote, 1000);
      expect(merged.physicalMs, 5000);
      expect(merged.counter, 4);
      expect(merged.nodeId, 'a', reason: 'identity stays local');
    });

    test('advances on a fresh wall clock ahead of both', () {
      const local = Hlc(physicalMs: 1000, counter: 7, nodeId: 'a');
      const remote = Hlc(physicalMs: 2000, counter: 7, nodeId: 'b');
      final merged = local.merge(remote, 9000);
      expect(merged.physicalMs, 9000);
      expect(merged.counter, 0);
    });

    test('keeps the local branch when it is ahead', () {
      const local = Hlc(physicalMs: 5000, counter: 2, nodeId: 'a');
      const remote = Hlc(physicalMs: 1000, counter: 9, nodeId: 'b');
      final merged = local.merge(remote, 1000);
      expect(merged.physicalMs, 5000);
      expect(merged.counter, 3);
    });
  });

  group('tie-breaking', () {
    test('is deterministic across devices', () {
      const a = Hlc(physicalMs: 1000, counter: 1, nodeId: 'aaa');
      const b = Hlc(physicalMs: 1000, counter: 1, nodeId: 'bbb');
      // Both devices must agree on the winner, whichever they are.
      expect(a.compareTo(b), lessThan(0));
      expect(b.compareTo(a), greaterThan(0));
      expect(b.dominates(a), isTrue);
    });

    test('an identical stamp dominates nothing', () {
      const a = Hlc(physicalMs: 1000, counter: 1, nodeId: 'aaa');
      const b = Hlc(physicalMs: 1000, counter: 1, nodeId: 'aaa');
      expect(a.dominates(b), isFalse);
      expect(a, equals(b));
    });
  });
}
