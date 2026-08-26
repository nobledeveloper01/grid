import '../value_objects/units.dart';

/// A generator or inverter the household runs when the grid is not there.
///
/// **State**, not a fact: it describes the household as it is now, and a user
/// who replaces a 2.5 kVA with a 5 kVA is correcting a description rather than
/// rewriting history.
class Generator {
  const Generator({
    required this.id,
    required this.meterId,
    required this.name,
    required this.ratedKva,
    required this.litresPerHour,
    this.fuel = FuelType.petrol,
  });

  final String id;
  final String meterId;
  final String name;

  /// Plate rating. Not what it delivers — see [deliveredKw].
  final double ratedKva;

  /// Consumption at the load the household actually runs, litres per hour.
  ///
  /// Measured by the user where possible: how long a full tank lasts is the
  /// one figure a household can establish for itself, and it beats any
  /// published curve because it already contains their real load.
  final double litresPerHour;

  final FuelType fuel;

  /// Usable output. A generator's kVA is apparent power; real power is lower
  /// by the power factor, and a set is not run at its plate rating for long.
  ///
  /// 0.8 power factor, 80% of rating. Both are conventions rather than
  /// measurements, which is why every figure derived from this is presented
  /// as an estimate.
  double get deliveredKw => ratedKva * 0.8 * 0.8;

  @override
  bool operator ==(Object other) => other is Generator && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

enum FuelType {
  petrol('Petrol'),
  diesel('Diesel');

  const FuelType(this.label);
  final String label;
}

/// Fuel bought. **A fact** — money left the household on a date.
class FuelPurchase {
  const FuelPurchase({
    required this.id,
    required this.meterId,
    required this.litres,
    required this.amount,
    required this.purchasedAt,
    this.generatorId,
  });

  final String id;
  final String meterId;
  final double litres;
  final Naira amount;
  final DateTime purchasedAt;
  final String? generatorId;

  /// What a litre cost on the day. The figure that moves fastest of anything
  /// in this product, which is why it is recorded per purchase rather than
  /// configured once.
  Naira get perLitre =>
      litres <= 0 ? Naira.zero : Naira.fromKobo((amount.kobo / litres).round());
}

/// A period the generator ran. **A fact.**
///
/// Recorded by hand, deliberately. Run-time could be inferred from charging
/// state the way grid supply is, and it would be wrong: a household with both
/// mains and a generator charges its phone from whichever is on, so the signal
/// cannot tell them apart. Guesswork dressed as measurement is the one thing
/// this product does not do.
class GeneratorRun {
  const GeneratorRun({
    required this.id,
    required this.meterId,
    required this.startedAt,
    this.endedAt,
    this.generatorId,
  });

  final String id;
  final String meterId;
  final DateTime startedAt;

  /// Null while it is still running.
  final DateTime? endedAt;

  final String? generatorId;

  bool get isRunning => endedAt == null;

  Duration elapsed(DateTime now) => (endedAt ?? now).difference(startedAt);

  double hours(DateTime now) => elapsed(now).inMinutes / 60.0;
}
