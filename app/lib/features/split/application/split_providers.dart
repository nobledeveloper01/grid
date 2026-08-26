import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/providers.dart';
import '../../../domain/services/allocation_engine.dart';
import '../../insights/application/insights_providers.dart';
import '../../meter/application/meter_providers.dart';
import '../data/receipt_renderer.dart';
import '../data/statement_client.dart';

final occupantsProvider =
    StreamProvider.family<List<Occupant>, String>((ref, meterId) {
  return ref.watch(occupantRepositoryProvider).watchForMeter(meterId);
});

/// The rule in force, as state. Stored per meter so a landlord with several
/// compounds does not have to keep switching it.
final splitRuleProvider =
    StreamProvider.family<SplitRule, String>((ref, meterId) {
  return ref
      .watch(settingsRepositoryProvider)
      .watch('split.$meterId.rule')
      .map((v) => SplitRule.values.firstWhere(
            (r) => r.name == v,
            orElse: () => SplitRule.equal,
          ));
});

/// How many days the split covers. One cycle by default.
const splitWindowDays = 30;

/// The split itself, recomputed whenever anything it rests on changes.
final allocationProvider =
    Provider.family<Allocation?, String>((ref, meterId) {
  final occupants = ref.watch(occupantsProvider(meterId)).value;
  if (occupants == null || occupants.isEmpty) return null;

  final rate = ref.watch(effectiveRateProvider(meterId));
  final series = ref.watch(
    consumptionSeriesProvider((meterId: meterId, days: splitWindowDays)),
  );
  if (rate == null || series == null || !series.hasData) return null;

  final now = ref.watch(clockProvider)();
  final rule = ref.watch(splitRuleProvider(meterId)).value ?? SplitRule.equal;

  return ref.watch(allocationEngineProvider).split(
        rule: rule,
        total: rate.costOf(series.total),
        totalEnergy: series.total,
        occupants: occupants,
        periodStart: now.subtract(const Duration(days: splitWindowDays)),
        periodEnd: now,
      );
});

class SplitController extends Notifier<void> {
  @override
  void build() {}

  Future<void> setRule(String meterId, SplitRule rule) => ref
      .read(settingsRepositoryProvider)
      .set('split.$meterId.rule', rule.name);

  Future<void> saveOccupant({
    required String meterId,
    required String name,
    int rooms = 1,
    double weight = 1,
    String? existingId,
  }) =>
      ref.read(occupantRepositoryProvider).save(
            meterId,
            Occupant(
              id: existingId ?? ref.read(uuidProvider).v7(),
              name: name,
              rooms: rooms,
              weight: weight,
            ),
          );

  Future<void> remove(String id) =>
      ref.read(occupantRepositoryProvider).remove(id);
}

final splitControllerProvider =
    NotifierProvider<SplitController, void>(SplitController.new);

/// One receipt per occupant, rendered and written beside the app's own files.
///
/// A PDF rather than an image, so it carries the arithmetic as selectable text
/// — a screenshot of a number is a number nobody can check.
final receiptFileProvider = FutureProvider.family<
    ({String path, Uint8List bytes}), ({String meterId, String shareId})>(
  (ref, args) async {
    final allocation = ref.watch(allocationProvider(args.meterId));
    final meter = ref.watch(selectedMeterProvider);
    if (allocation == null || meter == null) {
      throw StateError('nothing to render');
    }
    final share =
        allocation.shares.firstWhere((s) => s.occupant.id == args.shareId);

    final bytes = await const ReceiptRenderer()
        .render(allocation: allocation, share: share, meter: meter);

    final dir = await getApplicationDocumentsDirectory();
    final safe = share.occupant.name.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-');
    final stamp = allocation.periodEnd.toIso8601String().split('T').first;
    final path = '${dir.path}/grid-share-$safe-$stamp.pdf';
    await File(path).writeAsBytes(bytes, flush: true);
    return (path: path, bytes: bytes);
  },
);


const _serverKey = 'server.url';
const _apiKeyKey = 'server.key';

/// Where the landlord's Grid server is, and the key to talk to it.
///
/// Both are state and both are optional: everything else in the app works with
/// neither set, and a household with one meter never needs them. They exist so
/// a landlord can send tenants a link, which is the only outbound call the
/// application makes.
final serverUrlProvider = StreamProvider<String?>((ref) {
  return ref.watch(settingsRepositoryProvider).watch(_serverKey);
});

final serverKeyProvider = StreamProvider<String?>((ref) {
  return ref.watch(settingsRepositoryProvider).watch(_apiKeyKey);
});

final serverConfiguredProvider = Provider<bool>((ref) {
  final url = ref.watch(serverUrlProvider).value;
  final key = ref.watch(serverKeyProvider).value;
  return (url?.trim().isNotEmpty ?? false) && (key?.trim().isNotEmpty ?? false);
});

final statementClientProvider =
    Provider<StatementClient>((ref) => const StatementClient());

/// Statements issued in this session, so the landlord can send each link.
///
/// Deliberately not persisted. The links live on the server, which is the
/// thing that can revoke them; a stale copy on the phone would let a landlord
/// forward a link they had already killed.
class IssuedStatements extends Notifier<List<IssuedStatement>> {
  @override
  List<IssuedStatement> build() => const [];

  Future<void> issue(String meterId) async {
    final allocation = ref.read(allocationProvider(meterId));
    final occupants = ref.read(occupantsProvider(meterId)).value;
    final meter = ref.read(selectedMeterProvider);
    final url = ref.read(serverUrlProvider).value;
    final key = ref.read(serverKeyProvider).value;

    if (allocation == null || occupants == null || meter == null) {
      throw const StatementError('There is nothing to send yet.');
    }
    if (url == null || key == null || url.isEmpty || key.isEmpty) {
      throw const StatementError(
        'Set your server address and key in Settings first.',
      );
    }

    state = await ref.read(statementClientProvider).issue(
          baseUrl: url,
          apiKey: key,
          meterNumber: meter.meterNumber ?? meter.label,
          disco: meter.disco.label,
          allocation: allocation,
          occupants: occupants,
        );
  }

  void clear() => state = const [];
}

final issuedStatementsProvider =
    NotifierProvider<IssuedStatements, List<IssuedStatement>>(
  IssuedStatements.new,
);
