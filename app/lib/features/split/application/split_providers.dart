import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/providers.dart';
import '../../../domain/services/allocation_engine.dart';
import '../../insights/application/insights_providers.dart';
import '../../meter/application/meter_providers.dart';
import '../data/receipt_renderer.dart';

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
