import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/supply_event.dart';
import '../../../domain/value_objects/enums.dart';
import '../../meter/application/meter_providers.dart';

/// The currently open supply period, if any.
final ongoingSupplyProvider =
    Provider.family<SupplyEvent?, String>((ref, meterId) {
  final events = ref.watch(supplyEventsProvider(meterId)).value;
  if (events == null) return null;
  return events
      .where((e) => e.isOngoing && !e.isSuperseded)
      .firstOrNull;
});

class SupplyController extends Notifier<void> {
  @override
  void build() {}

  /// Closes the current period and opens the opposite one.
  ///
  /// Manual entries are recorded with `foregroundOnly` capability, because
  /// that is the honest description of what produced them: a person, in the
  /// app, at that moment.
  Future<void> toggle({required String meterId}) async {
    final repo = ref.read(supplyRepositoryProvider);
    final now = ref.read(clockProvider)();
    final ongoing = ref.read(ongoingSupplyProvider(meterId));

    final nextState = ongoing?.state == SupplyState.available
        ? SupplyState.unavailable
        : SupplyState.available;

    if (ongoing != null) {
      await repo.close(id: ongoing.id, endedAt: now);
    }

    await repo.add(
      SupplyEvent(
        id: ref.read(uuidProvider).v7(),
        meterId: meterId,
        state: nextState,
        startedAt: now,
        source: SupplySource.manual,
        platformCapability: PlatformCapability.foregroundOnly,
      ),
    );
  }
}

final supplyControllerProvider =
    NotifierProvider<SupplyController, void>(SupplyController.new);
