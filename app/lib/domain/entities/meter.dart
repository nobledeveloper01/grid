import '../value_objects/enums.dart';
import '../value_objects/units.dart';

/// A metering point. Everything in the product is scoped to one of these.
class Meter {
  const Meter({
    required this.id,
    required this.label,
    required this.type,
    required this.disco,
    required this.createdAt,
    this.meterNumber,
    this.tariffBand,
    this.rateOverride,
    this.digitCount,
    this.address,
    this.lga,
    this.parentMeterId,
    this.unitId,
    this.supplyDetectionEnabled = true,
    this.isArchived = false,
  });

  final String id;
  final String label;
  final MeterType type;
  final DisCo disco;
  final DateTime createdAt;

  /// Printed on the meter. Used in dispute packs.
  final String? meterNumber;

  final TariffBand? tariffBand;

  /// A manual ₦/kWh, overriding the bundled tariff table.
  final Rate? rateOverride;

  /// Expected register digits. Drives OCR digit-run selection.
  final int? digitCount;

  final String? address;
  final String? lga;

  /// Set when this is a sub-meter under another.
  final String? parentMeterId;
  final String? unitId;

  /// False for inverter and solar users, where charging state no longer
  /// tracks mains availability and the heuristic would be worse than nothing.
  final bool supplyDetectionEnabled;

  final bool isArchived;

  MeterDirection get direction => type.direction;
  bool get isPrepaid => type.isPrepaid;
  bool get isSubMeter => parentMeterId != null;

  Meter copyWith({
    String? label,
    MeterType? type,
    DisCo? disco,
    String? meterNumber,
    TariffBand? tariffBand,
    Rate? rateOverride,
    int? digitCount,
    String? address,
    String? lga,
    bool? supplyDetectionEnabled,
    bool? isArchived,
  }) {
    return Meter(
      id: id,
      label: label ?? this.label,
      type: type ?? this.type,
      disco: disco ?? this.disco,
      createdAt: createdAt,
      meterNumber: meterNumber ?? this.meterNumber,
      tariffBand: tariffBand ?? this.tariffBand,
      rateOverride: rateOverride ?? this.rateOverride,
      digitCount: digitCount ?? this.digitCount,
      address: address ?? this.address,
      lga: lga ?? this.lga,
      parentMeterId: parentMeterId,
      unitId: unitId,
      supplyDetectionEnabled:
          supplyDetectionEnabled ?? this.supplyDetectionEnabled,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  @override
  bool operator ==(Object other) => other is Meter && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
