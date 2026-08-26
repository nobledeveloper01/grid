import '../entities/generator.dart';
import '../value_objects/units.dart';

/// What generated power actually costs, and what the household pays in total.
///
/// Feature F9. Nobody in this market consumes only grid electricity, so the
/// real household figure is blended — grid units at the band tariff plus fuel
/// at whatever it cost this week. Households make this trade several times a
/// week and essentially none of them have the number.
sealed class GeneratorCost {
  const GeneratorCost();
}

/// Not enough logged to say anything. A first-class result, because the
/// alternative is a rate computed from one tank and presented as fact.
class GeneratorCostUnknown extends GeneratorCost {
  const GeneratorCostUnknown(this.reason, this.needed);

  final GeneratorGap reason;

  /// How many more of the missing thing would make this computable — drives
  /// "log two more runs" rather than "not enough data".
  final int needed;
}

enum GeneratorGap {
  noRuns,
  noFuel,

  /// Runs and fuel both exist but do not overlap in time, so dividing one by
  /// the other would price a month's fuel against a week's running.
  noOverlap,
}

class GeneratorCostKnown extends GeneratorCost {
  const GeneratorCostKnown({
    required this.hours,
    required this.litres,
    required this.spend,
    required this.energy,
    required this.rate,
    required this.runCount,
    required this.from,
    required this.to,
  });

  /// Hours run in the window.
  final double hours;

  /// Litres bought in the window.
  final double litres;

  /// What that fuel cost.
  final Naira spend;

  /// Energy the generator is modelled to have produced. **Modelled** — a
  /// generator has no meter, so this is delivered output times hours, and
  /// every figure downstream inherits that.
  final Kwh energy;

  /// Naira per kWh of generated power. The number this feature exists for.
  final Rate rate;

  final int runCount;
  final DateTime from;
  final DateTime to;

  /// Confidence is thin below this many runs; the UI shows a range instead.
  bool get isRough => runCount < 5;
}

/// Grid and generator side by side.
class BlendedCost {
  const BlendedCost({
    required this.gridEnergy,
    required this.gridRate,
    required this.gridSpend,
    required this.generatorEnergy,
    required this.generatorRate,
    required this.generatorSpend,
  });

  final Kwh gridEnergy;
  final Rate gridRate;
  final Naira gridSpend;

  final Kwh generatorEnergy;
  final Rate generatorRate;
  final Naira generatorSpend;

  Kwh get totalEnergy => gridEnergy + generatorEnergy;
  Naira get totalSpend => gridSpend + generatorSpend;

  /// The household's true rate across both sources.
  Rate get blendedRate => totalEnergy.isZero
      ? const Rate.fromKobo(0)
      : Rate.fromKobo((totalSpend.kobo * 1000 / totalEnergy.milli).round());

  /// How many times more expensive a generated unit is than a grid one.
  ///
  /// Null when the grid rate is zero, which is not a real tariff but is a
  /// perfectly reachable state for a meter with no band set.
  double? get multiple => gridRate.koboPerKwh == 0
      ? null
      : generatorRate.koboPerKwh / gridRate.koboPerKwh;

  /// Share of the household's energy that came off the generator, 0–1.
  double get generatorShare =>
      totalEnergy.isZero ? 0 : generatorEnergy.milli / totalEnergy.milli;
}

class GeneratorEngine {
  const GeneratorEngine();

  /// Minimum runs before a rate is offered at all.
  static const int minimumRuns = 2;

  /// Costs generated power over a window.
  ///
  /// Fuel and running are matched **within the same window** rather than over
  /// all history. Dividing a month of fuel by a week of running is the obvious
  /// way to produce a rate four times too low, and it looks entirely
  /// reasonable on screen.
  GeneratorCost cost({
    required List<GeneratorRun> runs,
    required List<FuelPurchase> fuel,
    required List<Generator> generators,
    required DateTime from,
    required DateTime to,
    required DateTime now,
  }) {
    final windowRuns = runs
        .where((r) => r.startedAt.isBefore(to) && !r.startedAt.isBefore(from))
        .toList();
    final windowFuel = fuel
        .where((f) =>
            f.purchasedAt.isBefore(to) && !f.purchasedAt.isBefore(from))
        .toList();

    if (windowRuns.length < minimumRuns) {
      return GeneratorCostUnknown(
        GeneratorGap.noRuns,
        minimumRuns - windowRuns.length,
      );
    }
    if (windowFuel.isEmpty) {
      return const GeneratorCostUnknown(GeneratorGap.noFuel, 1);
    }

    final hours = windowRuns.fold<double>(0, (a, r) => a + r.hours(now));
    if (hours <= 0) {
      return const GeneratorCostUnknown(GeneratorGap.noOverlap, 1);
    }

    final litres = windowFuel.fold<double>(0, (a, f) => a + f.litres);
    final spend =
        windowFuel.fold<Naira>(Naira.zero, (a, f) => a + f.amount);

    // Output is modelled from the set the runs name, or from the only one the
    // household has. With several generators and unattributed runs there is no
    // honest way to pick, so the mean is used and the result is rough by
    // construction — which `isRough` already says.
    final kw = _deliveredKw(windowRuns, generators);
    final energy = Kwh.fromDouble(kw * hours);

    if (energy.isZero) {
      return const GeneratorCostUnknown(GeneratorGap.noOverlap, 1);
    }

    return GeneratorCostKnown(
      hours: hours,
      litres: litres,
      spend: spend,
      energy: energy,
      rate: Rate.fromKobo((spend.kobo * 1000 / energy.milli).round()),
      runCount: windowRuns.length,
      from: from,
      to: to,
    );
  }

  double _deliveredKw(List<GeneratorRun> runs, List<Generator> generators) {
    if (generators.isEmpty) return 0;
    if (generators.length == 1) return generators.single.deliveredKw;

    final named = <String>{
      for (final r in runs)
        if (r.generatorId != null) r.generatorId!,
    };
    final used = generators.where((g) => named.contains(g.id)).toList();
    final pool = used.isEmpty ? generators : used;
    return pool.fold<double>(0, (a, g) => a + g.deliveredKw) / pool.length;
  }

  /// Grid and generator, side by side.
  BlendedCost blend({
    required Kwh gridEnergy,
    required Rate gridRate,
    required GeneratorCostKnown generator,
  }) {
    return BlendedCost(
      gridEnergy: gridEnergy,
      gridRate: gridRate,
      gridSpend: gridRate.costOf(gridEnergy),
      generatorEnergy: generator.energy,
      generatorRate: generator.rate,
      generatorSpend: generator.spend,
    );
  }

  /// What an hour of running costs, for the decision a household actually
  /// makes: run it now, or wait.
  Naira costPerHour({
    required GeneratorCostKnown cost,
  }) =>
      cost.hours <= 0
          ? Naira.zero
          : Naira.fromKobo((cost.spend.kobo / cost.hours).round());
}
