import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/providers.dart';
import '../../../domain/services/dispute_pack_engine.dart';
import '../../../domain/value_objects/units.dart';
import '../../meter/application/meter_providers.dart';
import '../data/pack_renderer.dart';

final disputePackEngineProvider =
    Provider<DisputePackEngine>((ref) => const DisputePackEngine());

final packRendererProvider =
    Provider<PackRenderer>((ref) => const PackRenderer());

/// What the user is building, held while they move through the steps.
class PackDraft {
  const PackDraft({
    this.kind = PackKind.bandShortfall,
    this.periodDays = 30,
    this.disputedAmount,
    this.narrative,
  });

  final PackKind kind;
  final int periodDays;
  final Naira? disputedAmount;
  final String? narrative;

  PackDraft copyWith({
    PackKind? kind,
    int? periodDays,
    Naira? disputedAmount,
    String? narrative,
    bool clearAmount = false,
  }) =>
      PackDraft(
        kind: kind ?? this.kind,
        periodDays: periodDays ?? this.periodDays,
        disputedAmount:
            clearAmount ? null : (disputedAmount ?? this.disputedAmount),
        narrative: narrative ?? this.narrative,
      );
}

class PackDraftNotifier extends Notifier<PackDraft> {
  @override
  PackDraft build() => const PackDraft();

  void setKind(PackKind k) => state = state.copyWith(kind: k);
  void setPeriod(int days) => state = state.copyWith(periodDays: days);
  void setAmount(Naira? amount) => state = amount == null
      ? state.copyWith(clearAmount: true)
      : state.copyWith(disputedAmount: amount);
  void setNarrative(String? text) => state = state.copyWith(narrative: text);
}

final packDraftProvider =
    NotifierProvider<PackDraftNotifier, PackDraft>(PackDraftNotifier.new);

/// Whether the draft can be built, and if not, why not in plain language.
final packEligibilityProvider =
    Provider.family<PackEligibility?, String>((ref, meterId) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  if (meter == null) return null;

  final readings = ref.watch(readingsProvider(meterId)).value;
  final supply = ref.watch(supplyEventsProvider(meterId)).value;
  if (readings == null || supply == null) return null;

  final draft = ref.watch(packDraftProvider);
  final now = ref.watch(clockProvider)();

  return ref.watch(disputePackEngineProvider).check(
        kind: draft.kind,
        meter: meter,
        readings: readings,
        supply: supply,
        periodStart: now.subtract(Duration(days: draft.periodDays)),
        periodEnd: now,
        now: now,
      );
});

/// The assembled pack, or null when it is not buildable yet.
final disputePackProvider =
    Provider.family<DisputePack?, String>((ref, meterId) {
  if (ref.watch(packEligibilityProvider(meterId)) is! PackReady) return null;

  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  if (meter == null) return null;

  final readings = ref.watch(readingsProvider(meterId)).value;
  final purchases = ref.watch(purchasesProvider(meterId)).value;
  final supply = ref.watch(supplyEventsProvider(meterId)).value;
  if (readings == null || purchases == null || supply == null) return null;

  final draft = ref.watch(packDraftProvider);
  final now = ref.watch(clockProvider)();
  final table = ref.watch(tariffTableProvider).value;

  return ref.watch(disputePackEngineProvider).build(
        kind: draft.kind,
        meter: meter,
        readings: readings,
        purchases: purchases,
        supply: supply,
        periodStart: now.subtract(Duration(days: draft.periodDays)),
        periodEnd: now,
        now: now,
        billedRate: ref.watch(effectiveRateProvider(meterId)),
        rateForBand: (b) => table?.rateFor(meter.disco, b),
        disputedAmount: draft.disputedAmount,
        narrative: draft.narrative,
      );
});

/// Renders the pack to a PDF and writes it beside the app's own files.
///
/// Entirely local: no upload, no server, and nothing about a dispute leaves
/// the device unless the user shares it themselves.
final packFileProvider =
    FutureProvider.family<({String path, Uint8List bytes}), String>(
        (ref, meterId) async {
  final pack = ref.watch(disputePackProvider(meterId));
  if (pack == null) throw StateError('no pack to render');

  final bytes = await ref.watch(packRendererProvider).render(pack);
  final dir = await getApplicationDocumentsDirectory();
  final stamp = pack.generatedAt.toIso8601String().split('T').first;
  final name = 'grid-${pack.kind.name}-$stamp.pdf';
  final file = await _write('${dir.path}/$name', bytes);
  return (path: file, bytes: bytes);
});

Future<String> _write(String path, Uint8List bytes) async {
  final f = File(path);
  await f.writeAsBytes(bytes, flush: true);
  return path;
}
