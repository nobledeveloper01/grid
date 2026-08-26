import '../value_objects/units.dart';

/// Splitting one meter's bill between the households behind it.
///
/// Feature F11, and the invariant phase 6's landlord console needs. One meter
/// serving several tenants is the default in Nigerian rented accommodation and
/// the split is settled by argument, because nobody can see the arithmetic.
///
/// The property this engine exists to guarantee is small and absolute:
///
/// > **The shares always sum to the total. Exactly. To the kobo.**
///
/// That is not a rounding preference. A split that loses ₦3 to rounding is a
/// split somebody can point at, and the point of showing the arithmetic is
/// that it survives being pointed at.
enum SplitRule {
  /// Everyone pays the same.
  equal('Equal shares', 'Everyone pays the same.'),

  /// Weighted by rooms occupied.
  byRooms('By rooms', 'Weighted by how many rooms each household has.'),

  /// Weighted by what each occupant's appliances are modelled to draw.
  byLoad('By what you run',
      'Weighted by the appliances each household actually runs.'),

  /// Explicit percentages, agreed in advance.
  manual('Agreed shares', 'Percentages everyone agreed to.');

  const SplitRule(this.label, this.description);
  final String label;
  final String description;
}

/// One household behind the meter.
class Occupant {
  const Occupant({
    required this.id,
    required this.name,
    this.rooms = 1,
    this.weight = 1,
    this.modelledDailyKwh,
  });

  final String id;
  final String name;

  /// For [SplitRule.byRooms].
  final int rooms;

  /// For [SplitRule.manual] — a percentage, or any consistent weight.
  final double weight;

  /// For [SplitRule.byLoad].
  final Kwh? modelledDailyKwh;
}

class Share {
  const Share({
    required this.occupant,
    required this.amount,
    required this.energy,
    required this.basis,
  });

  final Occupant occupant;
  final Naira amount;
  final Kwh energy;

  /// The weight this share was computed from, printed on the receipt so the
  /// arithmetic can be checked rather than trusted.
  final double basis;
}

/// A split, with everything needed to reproduce it later.
class Allocation {
  const Allocation({
    required this.rule,
    required this.periodStart,
    required this.periodEnd,
    required this.total,
    required this.totalEnergy,
    required this.shares,
    required this.remainderGivenTo,
  });

  final SplitRule rule;
  final DateTime periodStart;
  final DateTime periodEnd;

  final Naira total;
  final Kwh totalEnergy;
  final List<Share> shares;

  /// Who absorbed the indivisible remainder. Named rather than hidden: a few
  /// kobo has to land somewhere, and the receipt says where.
  final String? remainderGivenTo;

  /// The invariant, checkable by anyone holding the object.
  bool get sumsExactly =>
      shares.fold<int>(0, (a, s) => a + s.amount.kobo) == total.kobo;
}

class AllocationEngine {
  const AllocationEngine();

  /// Splits [total] between [occupants].
  ///
  /// Largest-remainder: every share is floored, and the kobo left over are
  /// handed out one at a time to whoever was rounded down hardest. Dividing
  /// and rounding each share independently is what loses money — three ways
  /// on ₦10,000 gives ₦3,333.33 each, and three of those is ₦9,999.99.
  Allocation split({
    required SplitRule rule,
    required Naira total,
    required Kwh totalEnergy,
    required List<Occupant> occupants,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) {
    if (occupants.isEmpty) {
      return Allocation(
        rule: rule,
        periodStart: periodStart,
        periodEnd: periodEnd,
        total: total,
        totalEnergy: totalEnergy,
        shares: const [],
        remainderGivenTo: null,
      );
    }

    final weights = [for (final o in occupants) _weightOf(rule, o)];
    final sum = weights.fold<double>(0, (a, w) => a + w);

    // Every weight zero — a load split where nobody has an inventory, say.
    // Falling back to equal shares is better than dividing by zero and much
    // better than charging one household the lot.
    final safe = sum <= 0
        ? List<double>.filled(occupants.length, 1)
        : weights;
    final safeSum = sum <= 0 ? occupants.length.toDouble() : sum;

    final exact = [
      for (final w in safe) total.kobo * w / safeSum,
    ];
    final floored = [for (final e in exact) e.floor()];
    var remainder = total.kobo - floored.fold<int>(0, (a, k) => a + k);

    // Hand the remainder to whoever lost the most to flooring, largest first.
    final order = List<int>.generate(occupants.length, (i) => i)
      ..sort((a, b) {
        final fa = exact[a] - floored[a];
        final fb = exact[b] - floored[b];
        final byFraction = fb.compareTo(fa);
        // Ties broken by position so the same input always produces the same
        // receipt — a split that changes between two viewings is a split
        // nobody believes.
        return byFraction != 0 ? byFraction : a.compareTo(b);
      });

    final kobo = [...floored];
    String? remainderTo;
    var i = 0;
    while (remainder > 0) {
      final at = order[i % order.length];
      kobo[at] += 1;
      remainderTo ??= occupants[at].name;
      remainder -= 1;
      i++;
    }

    return Allocation(
      rule: rule,
      periodStart: periodStart,
      periodEnd: periodEnd,
      total: total,
      totalEnergy: totalEnergy,
      remainderGivenTo: remainderTo,
      shares: [
        for (var n = 0; n < occupants.length; n++)
          Share(
            occupant: occupants[n],
            amount: Naira.fromKobo(kobo[n]),
            energy: Kwh.fromMilli(
              (totalEnergy.milli * safe[n] / safeSum).round(),
            ),
            basis: safe[n],
          ),
      ],
    );
  }

  double _weightOf(SplitRule rule, Occupant o) => switch (rule) {
        SplitRule.equal => 1,
        SplitRule.byRooms => o.rooms.toDouble(),
        SplitRule.byLoad => (o.modelledDailyKwh?.milli ?? 0).toDouble(),
        SplitRule.manual => o.weight,
      };
}
