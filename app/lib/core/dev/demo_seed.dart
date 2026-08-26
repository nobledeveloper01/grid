import 'dart:math';

import '../../domain/entities/appliance.dart';
import '../../domain/entities/meter.dart';
import '../../domain/entities/reading.dart';
import '../../domain/entities/supply_event.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/value_objects/enums.dart';
import '../../domain/value_objects/units.dart';

/// A realistic household, seeded on demand for development and QA.
///
/// Every screen in Grid is a function of months of accumulated facts, and
/// almost none of them can be judged — visually or otherwise — against the
/// two readings a fresh install has. Tapping through ninety days by hand to
/// look at a chart is not a workable loop.
///
/// Three rules keep this from becoming a liability:
///
/// 1. It is compiled in only under `--dart-define=GRID_DEMO=true`. A release
///    build has no path to it.
/// 2. It refuses to run against a database that already holds a meter, so it
///    can never sit alongside somebody's real record.
/// 3. The meter is named so that a screenshot of demo data is recognisable
///    as demo data at a glance.
///
/// The facts it writes go through the same repositories as everything else.
/// A seeded reading is an ordinary reading — there is no second write path,
/// and therefore no way for this to be the reason a bug does not reproduce.
class DemoSeed {
  const DemoSeed({
    required this.meters,
    required this.readings,
    required this.purchases,
    required this.supply,
    required this.appliances,
    required this.uuid,
  });

  final MeterRepository meters;
  final ReadingRepository readings;
  final PurchaseRepository purchases;
  final SupplyRepository supply;
  final ApplianceRepository appliances;
  final String Function() uuid;

  static const bool enabled =
      bool.fromEnvironment('GRID_DEMO', defaultValue: false);

  /// Seeds unless a meter already exists. Returns the meter id, or null if
  /// it declined.
  Future<String?> run({required DateTime now}) async {
    if (!enabled) return null;
    final existing = await meters.getAll();
    if (existing.isNotEmpty) return null;

    // A fixed seed, so the same demo produces the same screens. A chart that
    // looks different on every launch cannot be reviewed.
    final rng = Random(20260826);

    final meterId = uuid();
    final createdAt = now.subtract(const Duration(days: 104));

    await meters.save(Meter(
      id: meterId,
      label: 'Demo home',
      type: MeterType.postpaidDigital,
      disco: DisCo.ikeja,
      createdAt: createdAt,
      meterNumber: '04123456789',
      tariffBand: TariffBand.a,
      digitCount: 6,
      address: '14 Adelabu Street, Surulere',
      lga: 'Surulere',
    ));

    // --- Readings ---------------------------------------------------------
    // Ninety days, roughly every four to six days, at a household daily draw
    // that drifts with a weekly rhythm. One anomalous spike and one gap, so
    // the flagging and interpolation paths have something to render.
    var register = 38_400.0;
    var cursor = now.subtract(const Duration(days: 96));
    var index = 0;

    while (cursor.isBefore(now)) {
      final gapDays = 4 + rng.nextInt(3);
      final next = cursor.add(Duration(days: gapDays));
      if (next.isAfter(now)) break;

      // 9-13 kWh a day, higher at weekends.
      var daily = 9.0 + rng.nextDouble() * 2.5;
      if (next.weekday >= DateTime.saturday) daily += 1.6;
      register += daily * gapDays;

      // One deliberate spike, six weeks back: a reading that the validation
      // engine should flag and every baseline should exclude.
      final isSpike = index == 9;
      final value = isSpike ? register + 900 : register;

      await readings.add(Reading(
        id: uuid(),
        meterId: meterId,
        value: Kwh.fromDouble(value),
        readAt: DateTime(next.year, next.month, next.day, 7, 40),
        recordedAt: DateTime(next.year, next.month, next.day, 7, 41),
        source: index.isEven ? ReadingSource.manual : ReadingSource.ocr,
        ocrConfidence: index.isEven ? null : 0.86 + rng.nextDouble() * 0.12,
        flags: isSpike ? ReadingFlag.anomalousHigh.bit : 0,
      ));

      cursor = next;
      index++;
    }

    // --- Purchases --------------------------------------------------------
    // Postpaid households still buy nothing, but the demo meter carries a
    // couple of payments so the history screen is not half empty.
    for (var m = 3; m >= 1; m--) {
      await purchases.add(Purchase(
        id: uuid(),
        meterId: meterId,
        amount: Naira.fromNaira(25000 + rng.nextInt(12) * 500),
        purchasedAt: now.subtract(Duration(days: m * 30 - 2)),
      ));
    }

    // --- Supply -----------------------------------------------------------
    // Forty days of a Band A household that is not getting Band A service:
    // eleven to thirteen hours a day, in two or three blocks, with a handful
    // of unobserved windows so coverage lands realistically short of 100%.
    for (var d = 40; d >= 1; d--) {
      final day = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: d));

      // Every sixth day, leave a four-hour hole. Unobserved time is the
      // normal case on a phone, and the screens have to look right with it.
      final holeStart = d % 6 == 0 ? 13 : -1;

      var hour = 0;
      var onBudget = 10.5 + rng.nextDouble() * 2.5;

      final blocks = <(int, int, SupplyState)>[];
      while (hour < 24) {
        final isOn = onBudget > 0 && rng.nextDouble() < 0.45;
        var length = 2 + rng.nextInt(4);
        if (hour + length > 24) length = 24 - hour;
        if (isOn) {
          length = min(length, onBudget.ceil());
          onBudget -= length;
        }
        blocks.add((
          hour,
          hour + length,
          isOn ? SupplyState.available : SupplyState.unavailable,
        ));
        hour += length;
      }

      for (final (from, to, state) in blocks) {
        if (holeStart >= 0 && from >= holeStart && from < holeStart + 4) {
          continue; // unobserved
        }
        await supply.add(SupplyEvent(
          id: uuid(),
          meterId: meterId,
          state: state,
          startedAt: day.add(Duration(hours: from)),
          endedAt: day.add(Duration(hours: to)),
          source: SupplySource.inferredCharging,
          platformCapability: PlatformCapability.periodic,
        ));
      }
    }

    // --- Appliances -------------------------------------------------------
    const inventory = [
      ('Fridge', 150, 24.0, 1),
      ('Air conditioner', 1200, 6.0, 1),
      ('Freezer', 200, 24.0, 1),
      ('Television', 90, 5.0, 2),
      ('Pumping machine', 750, 0.6, 1),
      ('Electric iron', 1000, 0.4, 1),
      ('Lighting', 60, 6.0, 1),
      ('Water heater', 1500, 0.8, 1),
    ];
    for (final (name, watts, hours, count) in inventory) {
      await appliances.save(Appliance(
        id: uuid(),
        meterId: meterId,
        name: name,
        ratedWatts: watts,
        hoursPerDay: hours,
        quantity: count,
      ));
    }

    return meterId;
  }
}
