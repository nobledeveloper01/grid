import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/dispute_case.dart';
import '../../../domain/services/dispute_pack_engine.dart';
import '../../../domain/services/escalation_engine.dart';
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

final casesProvider =
    StreamProvider.family<List<DisputeCase>, String>((ref, meterId) {
  return ref.watch(disputeCaseRepositoryProvider).watchForMeter(meterId);
});

/// A case with its ladder position worked out.
typedef TrackedCase = ({DisputeCase caseRecord, EscalationState state});

final trackedCasesProvider =
    Provider.family<List<TrackedCase>, String>((ref, meterId) {
  final cases = ref.watch(casesProvider(meterId)).value ?? const [];
  final engine = ref.watch(escalationEngineProvider);
  final now = ref.watch(clockProvider)();
  return [
    for (final c in cases)
      (
        caseRecord: c,
        state: engine.evaluate(
          step: c.step,
          status: c.status,
          submittedAt: c.submittedAt,
          now: now,
        ),
      ),
  ];
});

/// Opens a case for a pack that has just been made.
///
/// Called when the pack is shared rather than when it is previewed: a
/// preview is somebody checking their own work, and a case list full of
/// drafts is a case list nobody trusts.
class CaseController extends Notifier<void> {
  @override
  void build() {}

  Future<DisputeCase> open({
    required DisputePack pack,
    required String packPath,
  }) async {
    final record = DisputeCase(
      id: ref.read(uuidProvider).v7(),
      meterId: pack.meter.id,
      kind: pack.kind.name,
      step: EscalationStep.businessUnit,
      status: CaseStatus.open,
      periodStart: pack.periodStart,
      periodEnd: pack.periodEnd,
      createdAt: pack.generatedAt,
      packPath: packPath,
    );
    await ref.read(disputeCaseRepositoryProvider).save(record);
    return record;
  }

  Future<void> markSubmitted(DisputeCase c, {String? reference}) =>
      ref.read(disputeCaseRepositoryProvider).save(
            c.copyWith(
              status: CaseStatus.awaitingResponse,
              submittedAt: ref.read(clockProvider)(),
              reference: reference,
            ),
          );

  /// Moves to the next rung. The clock restarts, because the wait belongs to
  /// the step and not to the case.
  Future<void> escalate(DisputeCase c) async {
    final next = c.step.next;
    if (next == null) return;
    await ref.read(disputeCaseRepositoryProvider).save(
          c.copyWith(
            step: next,
            status: CaseStatus.open,
            clearSubmittedAt: true,
          ),
        );
  }

  Future<void> setStatus(DisputeCase c, CaseStatus status) =>
      ref.read(disputeCaseRepositoryProvider).save(c.copyWith(status: status));

  Future<void> remove(DisputeCase c) =>
      ref.read(disputeCaseRepositoryProvider).remove(c.id);
}

final caseControllerProvider =
    NotifierProvider<CaseController, void>(CaseController.new);
