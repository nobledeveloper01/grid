import '../value_objects/units.dart';

/// An appliance in the user's inventory, used to model where consumption
/// goes. Modelled figures are always presented as estimates — never as
/// measurements.
class Appliance {
  const Appliance({
    required this.id,
    required this.name,
    required this.ratedWatts,
    required this.quantity,
    required this.hoursPerDay,
    this.meterId,
    this.unitId,
    this.catalogueKey,
    this.mainsOnly = true,
  });

  final String id;
  final String name;
  final int ratedWatts;
  final int quantity;
  final double hoursPerDay;
  final String? meterId;
  final String? unitId;
  final String? catalogueKey;

  /// When true, modelled hours are capped at measured daily supply hours —
  /// a freezer cannot run on grid power that was not there.
  final bool mainsOnly;

  /// Modelled daily consumption, before any supply-hours cap.
  Kwh get modelledDailyKwh =>
      Kwh.fromDouble(ratedWatts * quantity * hoursPerDay / 1000);

  /// Modelled daily consumption with [supplyHours] available. For mains-only
  /// appliances the running hours cannot exceed the hours power was present.
  Kwh modelledDailyKwhWithSupply(double supplyHours) {
    final effectiveHours =
        mainsOnly ? (hoursPerDay < supplyHours ? hoursPerDay : supplyHours)
                  : hoursPerDay;
    return Kwh.fromDouble(ratedWatts * quantity * effectiveHours / 1000);
  }

  Appliance copyWith({
    String? name,
    int? ratedWatts,
    int? quantity,
    double? hoursPerDay,
    bool? mainsOnly,
  }) {
    return Appliance(
      id: id,
      name: name ?? this.name,
      ratedWatts: ratedWatts ?? this.ratedWatts,
      quantity: quantity ?? this.quantity,
      hoursPerDay: hoursPerDay ?? this.hoursPerDay,
      meterId: meterId,
      unitId: unitId,
      catalogueKey: catalogueKey,
      mainsOnly: mainsOnly ?? this.mainsOnly,
    );
  }

  @override
  bool operator ==(Object other) => other is Appliance && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
