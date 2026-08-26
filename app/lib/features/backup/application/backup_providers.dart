import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/providers.dart';
import '../../../domain/services/backup_engine.dart';
import '../data/archive_cipher.dart';

final backupEngineProvider =
    Provider<BackupEngine>((ref) => const BackupEngine());

final archiveCipherProvider =
    Provider<ArchiveCipher>((ref) => const ArchiveCipher());

/// What a backup produced, so the screen can say something specific.
class BackupResult {
  const BackupResult({
    required this.path,
    required this.factCount,
    required this.bytes,
  });

  final String path;
  final int factCount;
  final int bytes;
}

class BackupController extends Notifier<void> {
  @override
  void build() {}

  /// Reads the whole record and writes one encrypted archive.
  ///
  /// Everything is read before anything is written, so a backup is a snapshot
  /// rather than a smear across whatever changed while it ran. Grid is a
  /// single-user application on a phone and the window is milliseconds — but a
  /// backup whose readings and supply log disagree about when it was taken is
  /// the kind of artefact that is impossible to reason about later.
  Future<BackupResult> create({required String passphrase}) async {
    final meters = await ref.read(meterRepositoryProvider).getAll();

    final readings = <dynamic>[];
    final purchases = <dynamic>[];
    final supply = <dynamic>[];
    final appliances = <dynamic>[];
    final generators = <dynamic>[];
    final fuel = <dynamic>[];
    final runs = <dynamic>[];

    for (final m in meters) {
      readings.addAll(await ref.read(readingRepositoryProvider).getForMeter(m.id));
      purchases
          .addAll(await ref.read(purchaseRepositoryProvider).getForMeter(m.id));
      supply.addAll(await ref.read(supplyRepositoryProvider).getForMeter(m.id));
      appliances
          .addAll(await ref.read(applianceRepositoryProvider).getForMeter(m.id));

      final gen = ref.read(generatorRepositoryProvider);
      generators.addAll(await gen.getGenerators(m.id));
      fuel.addAll(await gen.getFuel(m.id));
      runs.addAll(await gen.getRuns(m.id));
    }

    final archive = BackupArchive(
      version: BackupEngine.currentVersion,
      createdAt: ref.read(clockProvider)(),
      meters: meters,
      readings: readings.cast(),
      purchases: purchases.cast(),
      supply: supply.cast(),
      appliances: appliances.cast(),
      generators: generators.cast(),
      fuel: fuel.cast(),
      runs: runs.cast(),
      settings: await _settings(meters.map((m) => m.id)),
    );

    final json = ref.read(backupEngineProvider).encodeToJson(archive);
    final sealed = ref
        .read(archiveCipherProvider)
        .seal(plaintext: json, passphrase: passphrase);

    final dir = await getApplicationDocumentsDirectory();
    final stamp =
        archive.createdAt.toIso8601String().split('T').first;
    final path = '${dir.path}/grid-backup-$stamp.gridbak';
    await File(path).writeAsString(sealed, flush: true);

    return BackupResult(
      path: path,
      factCount: archive.factCount,
      bytes: sealed.length,
    );
  }

  /// Opens an archive and reports what it found, **without writing anything**.
  ///
  /// Restore is deliberately two steps. The user sees what is in the archive
  /// and what did not verify before any of it touches their record, because a
  /// restore that has already half-run is not something anyone can undo.
  Future<RestoreOutcome> inspect({
    required String envelope,
    required String passphrase,
  }) async {
    final json = ref
        .read(archiveCipherProvider)
        .open(envelope: envelope, passphrase: passphrase);

    if (json == null) {
      return const RestoreRefused(
        RestoreFailure.cannotOpen,
        'Grid could not open that file. Either the passphrase is wrong, or '
        'the archive has been altered since it was made — it cannot tell the '
        'two apart, and would rather say so than guess.',
      );
    }
    return ref.read(backupEngineProvider).decode(json);
  }

  /// Writes an inspected archive into the database.
  ///
  /// Facts are append-only, so a restore *adds* — it does not replace. An id
  /// that already exists is written again by `insertOnConflictUpdate` with
  /// identical content, which is a no-op in effect. Restoring the same archive
  /// twice therefore leaves the record exactly as it was, which is the
  /// behaviour somebody who is not sure whether the first attempt worked will
  /// rely on.
  Future<int> apply(BackupArchive archive) async {
    for (final m in archive.meters) {
      await ref.read(meterRepositoryProvider).save(m);
    }
    for (final r in archive.readings) {
      await ref.read(readingRepositoryProvider).add(r);
    }
    for (final p in archive.purchases) {
      await ref.read(purchaseRepositoryProvider).add(p);
    }
    for (final s in archive.supply) {
      await ref.read(supplyRepositoryProvider).add(s);
    }
    for (final a in archive.appliances) {
      await ref.read(applianceRepositoryProvider).save(a);
    }

    final gen = ref.read(generatorRepositoryProvider);
    for (final g in archive.generators) {
      await gen.saveGenerator(g);
    }
    for (final f in archive.fuel) {
      await gen.addFuel(f);
    }
    for (final r in archive.runs) {
      await gen.startRun(r);
    }

    final settings = ref.read(settingsRepositoryProvider);
    for (final e in archive.settings.entries) {
      await settings.set(e.key, e.value);
    }

    return archive.factCount;
  }

  /// The preference keys worth carrying. Enumerated rather than dumped, so a
  /// restore cannot resurrect a stale server key or a reminder flag that no
  /// longer means what it did.
  Future<Map<String, String>> _settings(Iterable<String> meterIds) async {
    final repo = ref.read(settingsRepositoryProvider);
    final keys = <String>[
      'reminders.on',
      'reminders.day',
      'reminders.asked',
      for (final id in meterIds) ...[
        'budget.$id.monthlyKobo',
        'budget.$id.payDay',
        'split.$id.rule',
      ],
    ];

    final out = <String, String>{};
    for (final k in keys) {
      final v = await repo.get(k);
      if (v != null && v.isNotEmpty) out[k] = v;
    }
    return out;
  }
}

final backupControllerProvider =
    NotifierProvider<BackupController, void>(BackupController.new);
