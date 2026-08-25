import '../../domain/entities/appliance.dart';
import '../../domain/entities/meter.dart';
import '../../domain/entities/reading.dart';
import '../../domain/entities/supply_event.dart';
import '../../domain/value_objects/enums.dart';
import '../../domain/value_objects/units.dart';
import 'database.dart';

/// Row <-> entity mapping.
///
/// Kept in the data layer so the domain never learns that Drift exists.
extension MeterRowMapper on MeterRow {
  Meter toDomain() => Meter(
        id: id,
        label: label,
        type: MeterType.values.byName(type),
        disco: DisCo.values.byName(disco),
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
        meterNumber: meterNumber,
        tariffBand: tariffBand == null
            ? null
            : TariffBand.values.byName(tariffBand!),
        rateOverride: rateOverrideKobo == null
            ? null
            : Rate.fromKobo(rateOverrideKobo!),
        digitCount: digitCount,
        address: address,
        lga: lga,
        parentMeterId: parentMeterId,
        unitId: unitId,
        supplyDetectionEnabled: supplyDetectionEnabled,
        isArchived: isArchived,
      );
}

extension ReadingRowMapper on ReadingRow {
  Reading toDomain() => Reading(
        id: id,
        meterId: meterId,
        value: Kwh.fromMilli(valueMilli),
        readAt: DateTime.fromMillisecondsSinceEpoch(readAt),
        recordedAt: DateTime.fromMillisecondsSinceEpoch(recordedAt),
        source: ReadingSource.values.byName(source),
        flags: flags,
        ocrConfidence: ocrConfidence,
        photoPath: photoPath,
        photoSha256: photoSha256,
        supersededById: supersededById,
        note: note,
      );
}

extension PurchaseRowMapper on PurchaseRow {
  Purchase toDomain() => Purchase(
        id: id,
        meterId: meterId,
        amount: Naira.fromKobo(amountKobo),
        units: unitsMilli == null ? null : Kwh.fromMilli(unitsMilli!),
        unitsDerived: unitsDerived,
        purchasedAt: DateTime.fromMillisecondsSinceEpoch(purchasedAt),
        tokenRef: tokenRef,
      );
}

extension SupplyEventRowMapper on SupplyEventRow {
  SupplyEvent toDomain() => SupplyEvent(
        id: id,
        meterId: meterId,
        state: SupplyState.values.byName(state),
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt),
        endedAt: endedAt == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(endedAt!),
        source: SupplySource.values.byName(source),
        platformCapability:
            PlatformCapability.values.byName(platformCapability),
        note: note,
        supersededById: supersededById,
      );
}

extension ApplianceRowMapper on ApplianceRow {
  Appliance toDomain() => Appliance(
        id: id,
        name: name,
        ratedWatts: ratedWatts,
        quantity: quantity,
        hoursPerDay: hoursPerDay,
        meterId: meterId,
        unitId: unitId,
        catalogueKey: catalogueKey,
        mainsOnly: mainsOnly,
      );
}
