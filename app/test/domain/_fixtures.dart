import 'package:grid/domain/entities/appliance.dart';
import 'package:grid/domain/entities/meter.dart';
import 'package:grid/domain/entities/reading.dart';
import 'package:grid/domain/entities/supply_event.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

/// A fixed reference instant so no test depends on the wall clock.
final now = DateTime(2026, 8, 25, 12);

Meter meter({
  MeterType type = MeterType.postpaidDigital,
  TariffBand? band = TariffBand.a,
  bool supplyDetection = true,
}) =>
    Meter(
      id: 'm1',
      label: 'Home',
      type: type,
      disco: DisCo.ikeja,
      createdAt: now.subtract(const Duration(days: 90)),
      tariffBand: band,
      supplyDetectionEnabled: supplyDetection,
    );

Reading reading({
  required String id,
  required double value,
  required DateTime at,
  int flags = 0,
  String? supersededById,
  ReadingSource source = ReadingSource.manual,
}) =>
    Reading(
      id: id,
      meterId: 'm1',
      value: Kwh.fromDouble(value),
      readAt: at,
      recordedAt: at,
      source: source,
      flags: flags,
      supersededById: supersededById,
    );

Purchase purchase({
  required String id,
  required double naira,
  double? units,
  required DateTime at,
}) =>
    Purchase(
      id: id,
      meterId: 'm1',
      amount: Naira.fromNaira(naira),
      units: units == null ? null : Kwh.fromDouble(units),
      purchasedAt: at,
    );

SupplyEvent supply({
  required String id,
  required SupplyState state,
  required DateTime from,
  DateTime? to,
  SupplySource source = SupplySource.manual,
  PlatformCapability capability = PlatformCapability.continuous,
}) =>
    SupplyEvent(
      id: id,
      meterId: 'm1',
      state: state,
      startedAt: from,
      endedAt: to,
      source: source,
      platformCapability: capability,
    );

Appliance appliance({
  required String id,
  required String name,
  required int watts,
  int quantity = 1,
  required double hours,
  bool mainsOnly = true,
}) =>
    Appliance(
      id: id,
      name: name,
      ratedWatts: watts,
      quantity: quantity,
      hoursPerDay: hours,
      meterId: 'm1',
      mainsOnly: mainsOnly,
    );

/// Builds a run of daily readings increasing by [perDay] kWh.
List<Reading> dailyRun({
  required double start,
  required double perDay,
  required int days,
  required DateTime endingAt,
}) {
  return [
    for (var i = days - 1; i >= 0; i--)
      reading(
        id: 'r$i',
        value: start + perDay * (days - 1 - i),
        at: endingAt.subtract(Duration(days: i)),
      ),
  ];
}
