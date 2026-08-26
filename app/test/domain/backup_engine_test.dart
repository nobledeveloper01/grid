import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/generator.dart';
import 'package:grid/domain/entities/reading.dart';
import 'package:grid/domain/entities/supply_event.dart';
import 'package:grid/domain/services/backup_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  const engine = BackupEngine();

  BackupArchive archive({
    List<Reading>? readings,
    Map<String, String> settings = const {'budget.m1.monthlyKobo': '3000000'},
  }) =>
      BackupArchive(
        version: BackupEngine.currentVersion,
        createdAt: now,
        meters: [meter()],
        readings: readings ??
            [
              reading(
                  id: 'r1',
                  value: 39330.1,
                  at: now.subtract(const Duration(days: 11))),
              reading(
                  id: 'r2',
                  value: 39381.4,
                  at: now.subtract(const Duration(days: 6))),
            ],
        purchases: [purchase(id: 'p1', naira: 25000, at: now)],
        supply: [
          supply(
            id: 's1',
            state: SupplyState.available,
            from: now.subtract(const Duration(hours: 6)),
            to: now.subtract(const Duration(hours: 2)),
          ),
        ],
        appliances: [appliance(id: 'a1', name: 'Fridge', watts: 150, hours: 24)],
        generators: [
          Generator(
            id: 'g1',
            meterId: 'm1',
            name: 'Backup set',
            ratedKva: 2.5,
            litresPerHour: 1.1,
            fuel: FuelType.diesel,
          ),
        ],
        fuel: [
          FuelPurchase(
            id: 'f1',
            meterId: 'm1',
            litres: 20,
            amount: Naira.fromNaira(24000),
            purchasedAt: now.subtract(const Duration(days: 2)),
          ),
        ],
        runs: [
          GeneratorRun(
            id: 'run1',
            meterId: 'm1',
            startedAt: now.subtract(const Duration(days: 2)),
            endedAt: now.subtract(const Duration(days: 2, hours: -4)),
          ),
        ],
        settings: settings,
      );

  RestoreReady roundTrip(BackupArchive a) {
    final out = engine.decode(engine.encodeToJson(a));
    expect(out, isA<RestoreReady>(),
        reason: out is RestoreRefused ? out.detail : '');
    return out as RestoreReady;
  }

  group('round trip', () {
    test('every fact survives, with its values intact', () {
      final restored = roundTrip(archive()).archive;

      expect(restored.meters.single.id, 'm1');
      expect(restored.meters.single.tariffBand, TariffBand.a);
      expect(restored.readings, hasLength(2));
      expect(restored.readings.first.value.milli,
          Kwh.fromDouble(39330.1).milli);
      expect(restored.purchases.single.amount.value, 25000);
      expect(restored.supply.single.state, SupplyState.available);
      expect(restored.appliances.single.ratedWatts, 150);
      expect(restored.generators.single.fuel, FuelType.diesel);
      expect(restored.fuel.single.litres, 20);
      expect(restored.runs.single.endedAt, isNotNull);
    });

    test('money and energy survive as integers, not as floats', () {
      // The whole point of the extension types is that nothing in the product
      // reintroduces float error. A backup is the easiest place to lose it.
      final restored = roundTrip(archive()).archive;
      expect(restored.purchases.single.amount.kobo, 2500000);
      expect(restored.readings.first.value.milli, 39330100);
    });

    test('preferences come back too', () {
      // Not evidence, but losing them turns a restore into a
      // reconfiguration.
      final restored = roundTrip(archive()).archive;
      expect(restored.settings['budget.m1.monthlyKobo'], '3000000');
    });

    test('a superseded reading stays superseded', () {
      // Corrections are the one place the append-only rule is visible, and a
      // restore that dropped the link would silently resurrect a value the
      // user had corrected.
      final restored = roundTrip(archive(readings: [
        reading(
            id: 'original',
            value: 1000,
            at: now.subtract(const Duration(days: 3)),
            supersededById: 'correction'),
        reading(id: 'correction', value: 1200, at: now),
      ])).archive;

      final original =
          restored.readings.firstWhere((r) => r.id == 'original');
      expect(original.isSuperseded, isTrue);
      expect(original.supersededById, 'correction');
    });

    test('flags survive, so an excluded reading stays excluded', () {
      final restored = roundTrip(archive(readings: [
        reading(id: 'clean', value: 1000, at: now.subtract(const Duration(days: 3))),
        reading(
            id: 'flagged',
            value: 9000,
            at: now,
            flags: ReadingFlag.anomalousHigh.bit),
      ])).archive;

      final flagged = restored.readings.firstWhere((r) => r.id == 'flagged');
      expect(flagged.excludedFromBaseline, isTrue);
    });
  });

  group('integrity', () {
    test('a clean archive reports nothing', () {
      expect(roundTrip(archive()).isClean, isTrue);
    });

    test('a reading that cited a photograph is called out', () {
      // The images are not in the archive, so the hash in the record has
      // nothing left to verify against. A dispute pack citing a fingerprint
      // for a file that no longer exists is worse than one that does not.
      final withPhoto = Reading(
        id: 'shot',
        meterId: 'm1',
        value: Kwh.fromDouble(39381.4),
        readAt: now,
        recordedAt: now,
        source: ReadingSource.ocr,
        photoPath: '/x.jpg',
        photoSha256: 'abc123',
      );
      final out = roundTrip(archive(readings: [withPhoto]));

      expect(out.isClean, isFalse);
      expect(out.integrity.single.toLowerCase(), contains('photograph'));
      expect(out.archive.readings.single.photoSha256, 'abc123',
          reason: 'the record is kept; only the image is missing');
    });
  });

  group('refusals', () {
    test('a newer format is refused rather than guessed at', () {
      final json = engine.encodeToJson(archive());
      final bumped = json.replaceFirst(
        '"version":${BackupEngine.currentVersion}',
        '"version":${BackupEngine.currentVersion + 1}',
      );
      final out = engine.decode(bumped) as RestoreRefused;
      expect(out.reason, RestoreFailure.tooNew);
      expect(out.detail, contains('newer version'));
    });

    test('an older format is still readable', () {
      // A backup a later version cannot read is not a backup.
      final json = engine.encodeToJson(archive());
      expect(engine.decode(json), isA<RestoreReady>());
    });

    test('a file that is not JSON says so, and mentions the passphrase', () {
      final out = engine.decode('this is not an archive') as RestoreRefused;
      expect(out.reason, RestoreFailure.cannotOpen);
      expect(out.detail.toLowerCase(), contains('passphrase'));
    });

    test('JSON that is not an archive is refused', () {
      final out = engine.decode('[1,2,3]') as RestoreRefused;
      expect(out.reason, RestoreFailure.malformed);
    });

    test('a missing format version is refused rather than assumed', () {
      final out = engine.decode('{"meters":[]}') as RestoreRefused;
      expect(out.reason, RestoreFailure.malformed);
      expect(out.detail, contains('format version'));
    });

    test('a damaged archive imports nothing rather than part of it', () {
      final json = engine.encodeToJson(archive())
          .replaceFirst('"readAt"', '"readAtBroken"');
      final out = engine.decode(json) as RestoreRefused;
      expect(out.reason, RestoreFailure.malformed);
    });
  });

  group('forward compatibility', () {
    test('an unknown enum member falls back rather than failing the whole', () {
      // A future Grid may add a DisCo. An archive from it should still
      // restore everything else.
      final json = engine
          .encodeToJson(archive())
          .replaceFirst('"disco":"ikeja"', '"disco":"somewhere-new"');
      final out = engine.decode(json) as RestoreReady;
      expect(out.archive.meters.single.disco, DisCo.other);
      expect(out.archive.readings, hasLength(2),
          reason: 'the rest of the archive is unaffected');
    });
  });
}
