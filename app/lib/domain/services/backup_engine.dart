import 'dart:convert';

import '../entities/appliance.dart';
import '../entities/generator.dart';
import '../entities/meter.dart';
import '../entities/reading.dart';
import '../entities/supply_event.dart';
import '../value_objects/enums.dart';
import '../value_objects/units.dart';

/// Turning the record into an archive, and back.
///
/// Feature F13. Grid holds two years of evidence in a local database and there
/// is no server until phase 6 — and phase 6 does not sync facts. An evidence
/// product with no recovery path is one dropped phone away from having
/// nothing, which makes this the least glamorous feature in the backlog and
/// one of the few that is genuinely load-bearing.
///
/// The engine deals only in the *shape* of the archive: what goes in, how it
/// is versioned, and what a restore is allowed to accept. Encryption and file
/// writing live in the data layer, because the domain must stay free of both
/// `dart:io` and a crypto package.
class BackupArchive {
  const BackupArchive({
    required this.version,
    required this.createdAt,
    required this.meters,
    required this.readings,
    required this.purchases,
    required this.supply,
    required this.appliances,
    required this.generators,
    required this.fuel,
    required this.runs,
    required this.settings,
  });

  /// The archive format, not the app version.
  ///
  /// Versioned from the first release, because a backup a later version cannot
  /// read is not a backup. A restore refuses anything newer than it
  /// understands rather than guessing at fields it has never seen.
  final int version;

  final DateTime createdAt;

  final List<Meter> meters;
  final List<Reading> readings;
  final List<Purchase> purchases;
  final List<SupplyEvent> supply;
  final List<Appliance> appliances;
  final List<Generator> generators;
  final List<FuelPurchase> fuel;
  final List<GeneratorRun> runs;

  /// Preferences — budget, split rule, reminder day. Not evidence, but losing
  /// them turns a restore into a reconfiguration.
  final Map<String, String> settings;

  int get factCount =>
      readings.length + purchases.length + supply.length + fuel.length +
          runs.length;
}

/// What a restore found. A result rather than an exception, because most of
/// these are things the user can act on.
sealed class RestoreOutcome {
  const RestoreOutcome();
}

class RestoreReady extends RestoreOutcome {
  const RestoreReady(this.archive, this.integrity);

  final BackupArchive archive;

  /// What did not verify. Empty on a clean archive.
  final List<String> integrity;

  bool get isClean => integrity.isEmpty;
}

enum RestoreFailure {
  /// The passphrase did not decrypt it, or the file is not one of ours.
  cannotOpen,

  /// Written by a newer version of Grid than this one.
  tooNew,

  /// Opened, but the contents are not an archive.
  malformed,
}

class RestoreRefused extends RestoreOutcome {
  const RestoreRefused(this.reason, this.detail);

  final RestoreFailure reason;
  final String detail;
}

class BackupEngine {
  const BackupEngine();

  /// The format this version writes, and the newest it will read.
  static const int currentVersion = 1;

  /// Serialises the record.
  ///
  /// Plain JSON rather than the database file. A SQLite file is tied to the
  /// schema version that produced it, so restoring one into a later Grid means
  /// replaying every migration against a database somebody else's phone wrote.
  /// JSON costs size and buys the ability to restore an archive written two
  /// years and four migrations ago.
  Map<String, dynamic> encode(BackupArchive a) => {
        'version': a.version,
        'createdAt': a.createdAt.toIso8601String(),
        'meters': [for (final m in a.meters) _meter(m)],
        'readings': [for (final r in a.readings) _reading(r)],
        'purchases': [for (final p in a.purchases) _purchase(p)],
        'supply': [for (final s in a.supply) _supply(s)],
        'appliances': [for (final x in a.appliances) _appliance(x)],
        'generators': [for (final g in a.generators) _generator(g)],
        'fuel': [for (final f in a.fuel) _fuel(f)],
        'runs': [for (final r in a.runs) _run(r)],
        'settings': a.settings,
      };

  String encodeToJson(BackupArchive a) => jsonEncode(encode(a));

  /// Reads an archive back, refusing rather than guessing.
  RestoreOutcome decode(String json) {
    final Map<String, dynamic> raw;
    try {
      final decoded = jsonDecode(json);
      if (decoded is! Map<String, dynamic>) {
        return const RestoreRefused(
          RestoreFailure.malformed,
          'That file opened, but it is not a Grid backup.',
        );
      }
      raw = decoded;
    } on FormatException {
      return const RestoreRefused(
        RestoreFailure.cannotOpen,
        'Grid could not open that file. Check the passphrase is the one you '
        'set when you made the backup.',
      );
    }

    final version = raw['version'];
    if (version is! int) {
      return const RestoreRefused(
        RestoreFailure.malformed,
        'That file is missing its format version, so Grid cannot tell how to '
        'read it.',
      );
    }
    if (version > currentVersion) {
      return RestoreRefused(
        RestoreFailure.tooNew,
        'That backup was written by a newer version of Grid (format '
        '$version; this one reads up to $currentVersion). Update the app and '
        'try again — reading it now would mean guessing at fields this '
        'version has never seen.',
      );
    }

    try {
      final integrity = <String>[];

      final readings = [
        for (final r in _list(raw['readings']))
          _readReading(r, integrity),
      ];

      return RestoreReady(
        BackupArchive(
          version: version,
          createdAt:
              DateTime.tryParse(raw['createdAt'] as String? ?? '') ??
                  DateTime.fromMillisecondsSinceEpoch(0),
          meters: [for (final m in _list(raw['meters'])) _readMeter(m)],
          readings: readings,
          purchases: [
            for (final p in _list(raw['purchases'])) _readPurchase(p),
          ],
          supply: [for (final s in _list(raw['supply'])) _readSupply(s)],
          appliances: [
            for (final a in _list(raw['appliances'])) _readAppliance(a),
          ],
          generators: [
            for (final g in _list(raw['generators'])) _readGenerator(g),
          ],
          fuel: [for (final f in _list(raw['fuel'])) _readFuel(f)],
          runs: [for (final r in _list(raw['runs'])) _readRun(r)],
          settings: {
            for (final e in (raw['settings'] as Map? ?? {}).entries)
              e.key.toString(): e.value.toString(),
          },
        ),
        integrity,
      );
    } on Object catch (e) {
      return RestoreRefused(
        RestoreFailure.malformed,
        'That backup is damaged and Grid stopped rather than importing part '
        'of it: $e',
      );
    }
  }

  List<Map<String, dynamic>> _list(Object? v) => [
        for (final e in (v as List<dynamic>? ?? const []))
          e as Map<String, dynamic>,
      ];

  // --- writing --------------------------------------------------------------

  Map<String, dynamic> _meter(Meter m) => {
        'id': m.id,
        'label': m.label,
        'type': m.type.name,
        'disco': m.disco.name,
        'createdAt': m.createdAt.toIso8601String(),
        'meterNumber': m.meterNumber,
        'tariffBand': m.tariffBand?.name,
        'rateOverrideKobo': m.rateOverride?.koboPerKwh,
        'digitCount': m.digitCount,
        'address': m.address,
        'lga': m.lga,
        'supplyDetectionEnabled': m.supplyDetectionEnabled,
      };

  Map<String, dynamic> _reading(Reading r) => {
        'id': r.id,
        'meterId': r.meterId,
        'milli': r.value.milli,
        'readAt': r.readAt.toIso8601String(),
        'recordedAt': r.recordedAt.toIso8601String(),
        'source': r.source.name,
        'flags': r.flags,
        'ocrConfidence': r.ocrConfidence,
        'photoPath': r.photoPath,
        'photoSha256': r.photoSha256,
        'supersededById': r.supersededById,
        'note': r.note,
      };

  Map<String, dynamic> _purchase(Purchase p) => {
        'id': p.id,
        'meterId': p.meterId,
        'kobo': p.amount.kobo,
        'unitsMilli': p.units?.milli,
        'unitsDerived': p.unitsDerived,
        'purchasedAt': p.purchasedAt.toIso8601String(),
        'tokenRef': p.tokenRef,
      };

  Map<String, dynamic> _supply(SupplyEvent s) => {
        'id': s.id,
        'meterId': s.meterId,
        'state': s.state.name,
        'startedAt': s.startedAt.toIso8601String(),
        'endedAt': s.endedAt?.toIso8601String(),
        'source': s.source.name,
        'capability': s.platformCapability.name,
        'supersededById': s.supersededById,
      };

  Map<String, dynamic> _appliance(Appliance a) => {
        'id': a.id,
        'meterId': a.meterId,
        'name': a.name,
        'ratedWatts': a.ratedWatts,
        'quantity': a.quantity,
        'hoursPerDay': a.hoursPerDay,
        'mainsOnly': a.mainsOnly,
        'catalogueKey': a.catalogueKey,
      };

  Map<String, dynamic> _generator(Generator g) => {
        'id': g.id,
        'meterId': g.meterId,
        'name': g.name,
        'ratedKva': g.ratedKva,
        'litresPerHour': g.litresPerHour,
        'fuel': g.fuel.name,
      };

  Map<String, dynamic> _fuel(FuelPurchase f) => {
        'id': f.id,
        'meterId': f.meterId,
        'generatorId': f.generatorId,
        'litres': f.litres,
        'kobo': f.amount.kobo,
        'purchasedAt': f.purchasedAt.toIso8601String(),
      };

  Map<String, dynamic> _run(GeneratorRun r) => {
        'id': r.id,
        'meterId': r.meterId,
        'generatorId': r.generatorId,
        'startedAt': r.startedAt.toIso8601String(),
        'endedAt': r.endedAt?.toIso8601String(),
      };

  // --- reading --------------------------------------------------------------

  Meter _readMeter(Map<String, dynamic> m) => Meter(
        id: m['id'] as String,
        label: m['label'] as String,
        type: _enum(MeterType.values, m['type'], MeterType.prepaidKeypad),
        disco: _enum(DisCo.values, m['disco'], DisCo.other),
        createdAt: DateTime.parse(m['createdAt'] as String),
        meterNumber: m['meterNumber'] as String?,
        tariffBand: m['tariffBand'] == null
            ? null
            : _enum(TariffBand.values, m['tariffBand'], TariffBand.e),
        rateOverride: m['rateOverrideKobo'] == null
            ? null
            : Rate.fromKobo((m['rateOverrideKobo'] as num).toInt()),
        digitCount: (m['digitCount'] as num?)?.toInt(),
        address: m['address'] as String?,
        lga: m['lga'] as String?,
        supplyDetectionEnabled:
            m['supplyDetectionEnabled'] as bool? ?? true,
      );

  Reading _readReading(Map<String, dynamic> r, List<String> integrity) {
    final reading = Reading(
      id: r['id'] as String,
      meterId: r['meterId'] as String,
      value: Kwh.fromMilli((r['milli'] as num).toInt()),
      readAt: DateTime.parse(r['readAt'] as String),
      recordedAt: DateTime.parse(r['recordedAt'] as String),
      source: _enum(ReadingSource.values, r['source'], ReadingSource.manual),
      flags: (r['flags'] as num?)?.toInt() ?? 0,
      ocrConfidence: (r['ocrConfidence'] as num?)?.toDouble(),
      photoPath: r['photoPath'] as String?,
      photoSha256: r['photoSha256'] as String?,
      supersededById: r['supersededById'] as String?,
      note: r['note'] as String?,
    );

    // A reading that claimed a photograph is worth flagging on restore: the
    // image files are not inside the archive, so the hash in the record has
    // nothing left to verify against. Better to say so than to let a dispute
    // pack cite a fingerprint for a file that no longer exists.
    if (reading.photoSha256 != null) {
      integrity.add(
        'The reading of ${reading.value.formatValue()} on '
        '${reading.readAt.toIso8601String().split('T').first} referenced a '
        'photograph. Photographs are not carried in the archive, so it will '
        'restore without its image.',
      );
    }
    return reading;
  }

  Purchase _readPurchase(Map<String, dynamic> p) => Purchase(
        id: p['id'] as String,
        meterId: p['meterId'] as String,
        amount: Naira.fromKobo((p['kobo'] as num).toInt()),
        units: p['unitsMilli'] == null
            ? null
            : Kwh.fromMilli((p['unitsMilli'] as num).toInt()),
        unitsDerived: p['unitsDerived'] as bool? ?? false,
        purchasedAt: DateTime.parse(p['purchasedAt'] as String),
        tokenRef: p['tokenRef'] as String?,
      );

  SupplyEvent _readSupply(Map<String, dynamic> s) => SupplyEvent(
        id: s['id'] as String,
        meterId: s['meterId'] as String,
        state: _enum(SupplyState.values, s['state'], SupplyState.unknown),
        startedAt: DateTime.parse(s['startedAt'] as String),
        endedAt: s['endedAt'] == null
            ? null
            : DateTime.parse(s['endedAt'] as String),
        source: _enum(SupplySource.values, s['source'], SupplySource.imported),
        platformCapability: _enum(PlatformCapability.values, s['capability'],
            PlatformCapability.foregroundOnly),
        supersededById: s['supersededById'] as String?,
      );

  Appliance _readAppliance(Map<String, dynamic> a) => Appliance(
        id: a['id'] as String,
        meterId: a['meterId'] as String?,
        name: a['name'] as String,
        ratedWatts: (a['ratedWatts'] as num).toInt(),
        quantity: (a['quantity'] as num?)?.toInt() ?? 1,
        hoursPerDay: (a['hoursPerDay'] as num).toDouble(),
        mainsOnly: a['mainsOnly'] as bool? ?? true,
        catalogueKey: a['catalogueKey'] as String?,
      );

  Generator _readGenerator(Map<String, dynamic> g) => Generator(
        id: g['id'] as String,
        meterId: g['meterId'] as String,
        name: g['name'] as String,
        ratedKva: (g['ratedKva'] as num).toDouble(),
        litresPerHour: (g['litresPerHour'] as num).toDouble(),
        fuel: _enum(FuelType.values, g['fuel'], FuelType.petrol),
      );

  FuelPurchase _readFuel(Map<String, dynamic> f) => FuelPurchase(
        id: f['id'] as String,
        meterId: f['meterId'] as String,
        generatorId: f['generatorId'] as String?,
        litres: (f['litres'] as num).toDouble(),
        amount: Naira.fromKobo((f['kobo'] as num).toInt()),
        purchasedAt: DateTime.parse(f['purchasedAt'] as String),
      );

  GeneratorRun _readRun(Map<String, dynamic> r) => GeneratorRun(
        id: r['id'] as String,
        meterId: r['meterId'] as String,
        generatorId: r['generatorId'] as String?,
        startedAt: DateTime.parse(r['startedAt'] as String),
        endedAt: r['endedAt'] == null
            ? null
            : DateTime.parse(r['endedAt'] as String),
      );

  /// Falls back rather than throwing on an unknown name.
  ///
  /// A future Grid may add a DisCo or a supply source. An archive from it
  /// should still restore everything else rather than failing whole because
  /// one enum grew a member.
  T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
