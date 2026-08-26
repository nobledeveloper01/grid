import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/allocation_engine.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  const engine = AllocationEngine();

  Allocation split({
    SplitRule rule = SplitRule.equal,
    double naira = 10000,
    double kwh = 100,
    required List<Occupant> occupants,
  }) =>
      engine.split(
        rule: rule,
        total: Naira.fromNaira(naira),
        totalEnergy: Kwh.fromDouble(kwh),
        occupants: occupants,
        periodStart: now.subtract(const Duration(days: 30)),
        periodEnd: now,
      );

  List<Occupant> people(int n) => [
        for (var i = 0; i < n; i++)
          Occupant(id: 'o$i', name: 'Flat ${i + 1}'),
      ];

  group('the invariant', () {
    test('three ways on ten thousand loses nothing', () {
      // Dividing and rounding each share independently gives 3,333.33 each,
      // and three of those is 9,999.99. The missing kobo is the whole reason
      // this engine exists.
      final a = split(occupants: people(3));
      expect(a.sumsExactly, isTrue);
      expect(a.total.kobo, 1000000);
      expect(a.shares.fold<int>(0, (s, x) => s + x.amount.kobo), 1000000);
    });

    test('holds for every awkward combination anyone is likely to hit', () {
      for (final n in [1, 2, 3, 4, 5, 6, 7, 9, 11, 13]) {
        for (final amount in [1, 7, 99, 1000, 12345, 999999, 1234567]) {
          final a = split(naira: amount / 100, occupants: people(n));
          expect(a.sumsExactly, isTrue,
              reason: '$n ways on $amount kobo did not sum exactly');
        }
      }
    });

    test('holds under random weights, which is where rounding hides', () {
      final rng = Random(20260826);
      for (var trial = 0; trial < 300; trial++) {
        final n = 2 + rng.nextInt(6);
        final occupants = [
          for (var i = 0; i < n; i++)
            Occupant(
              id: 'o$i',
              name: 'Flat $i',
              weight: 1 + rng.nextDouble() * 20,
            ),
        ];
        final a = split(
          rule: SplitRule.manual,
          naira: (1 + rng.nextInt(500000)) / 100,
          occupants: occupants,
        );
        expect(a.sumsExactly, isTrue,
            reason: 'trial $trial with $n occupants did not sum exactly');
      }
    });

    test('one occupant pays the whole thing', () {
      final a = split(occupants: people(1));
      expect(a.shares.single.amount.kobo, a.total.kobo);
    });

    test('nobody behind the meter allocates nothing rather than throwing', () {
      final a = split(occupants: const []);
      expect(a.shares, isEmpty);
      expect(a.sumsExactly, isFalse,
          reason: 'no shares cannot sum to a non-zero total, and saying so is '
              'better than pretending');
    });
  });

  group('the remainder', () {
    test('goes to whoever was rounded down hardest, and is named', () {
      final a = split(naira: 100.01, occupants: people(3));
      expect(a.remainderGivenTo, isNotNull);
      expect(a.sumsExactly, isTrue);
      // Two get 3,333 kobo and one gets 3,335 — or some such; what matters is
      // that the difference is at most a kobo per person per remainder unit.
      final amounts = a.shares.map((s) => s.amount.kobo).toList()..sort();
      expect(amounts.last - amounts.first, lessThanOrEqualTo(2));
    });

    test('is nobody when the division is clean', () {
      final a = split(naira: 9000, occupants: people(3));
      expect(a.remainderGivenTo, isNull);
      expect(a.shares.every((s) => s.amount.kobo == 300000), isTrue);
    });

    test('the same input always produces the same receipt', () {
      // A split that changes between two viewings is a split nobody believes.
      final first = split(naira: 100.07, occupants: people(4));
      final second = split(naira: 100.07, occupants: people(4));
      expect(
        first.shares.map((s) => s.amount.kobo),
        second.shares.map((s) => s.amount.kobo),
      );
      expect(first.remainderGivenTo, second.remainderGivenTo);
    });
  });

  group('the rules', () {
    test('by rooms weights the bigger flat higher', () {
      final a = split(
        rule: SplitRule.byRooms,
        naira: 12000,
        occupants: const [
          Occupant(id: 'a', name: 'Two rooms', rooms: 2),
          Occupant(id: 'b', name: 'One room'),
        ],
      );
      expect(a.shares.first.amount.value, closeTo(8000, 0.01));
      expect(a.shares.last.amount.value, closeTo(4000, 0.01));
      expect(a.sumsExactly, isTrue);
    });

    test('by load weights the heavier household higher', () {
      final a = split(
        rule: SplitRule.byLoad,
        naira: 10000,
        occupants: [
          Occupant(
              id: 'a', name: 'Air conditioner', modelledDailyKwh: Kwh.fromDouble(9)),
          Occupant(id: 'b', name: 'Fan', modelledDailyKwh: Kwh.fromDouble(1)),
        ],
      );
      expect(a.shares.first.amount.value, closeTo(9000, 0.01));
      expect(a.sumsExactly, isTrue);
    });

    test('a load split with no inventories falls back to equal shares', () {
      // Better than dividing by zero, and much better than charging one
      // household the lot.
      final a = split(rule: SplitRule.byLoad, occupants: people(4));
      expect(a.sumsExactly, isTrue);
      expect(a.shares.every((s) => s.amount.kobo == 250000), isTrue);
    });

    test('energy is split on the same basis as the money', () {
      final a = split(
        rule: SplitRule.byRooms,
        kwh: 300,
        occupants: const [
          Occupant(id: 'a', name: 'Two', rooms: 2),
          Occupant(id: 'b', name: 'One'),
        ],
      );
      expect(a.shares.first.energy.value, closeTo(200, 0.1));
      expect(a.shares.last.energy.value, closeTo(100, 0.1));
    });

    test('every share carries the weight it was computed from', () {
      final a = split(
        rule: SplitRule.byRooms,
        occupants: const [
          Occupant(id: 'a', name: 'Two', rooms: 2),
          Occupant(id: 'b', name: 'One'),
        ],
      );
      expect(a.shares.first.basis, 2);
      expect(a.shares.last.basis, 1);
    });
  });
}
