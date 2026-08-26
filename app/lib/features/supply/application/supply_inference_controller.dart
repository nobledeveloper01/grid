import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/platform/supply_monitor.dart';
import '../../../domain/entities/supply_event.dart';
import '../../../domain/services/supply_inference_engine.dart';
import '../../../domain/value_objects/enums.dart';
import '../../meter/application/meter_providers.dart';

/// Runs charging-state inference for the selected meter.
///
/// Listens to the platform, debounces through [SupplyInferenceEngine], and
/// writes supply events. It samples on every foreground as well as on every
/// platform event, because on both platforms the stream is sparse and a
/// foreground is the one moment the app is certainly alive.
class SupplyInferenceController with WidgetsBindingObserver {
  SupplyInferenceController(this.ref);

  final Ref ref;

  StreamSubscription<PowerSample>? _subscription;
  PowerObservation? _pending;
  PlatformCapability _capability = PlatformCapability.foregroundOnly;
  String? _meterId;

  Future<void> start(String meterId) async {
    if (_meterId == meterId && _subscription != null) return;
    await stop();
    _meterId = meterId;

    final meter = ref
        .read(metersProvider)
        .value
        ?.where((m) => m.id == meterId)
        .firstOrNull;

    // A user on an inverter told us charging state means nothing here. Taking
    // samples anyway would fabricate a timeline.
    if (meter == null || !meter.supplyDetectionEnabled) return;

    final monitor = ref.read(supplyMonitorProvider);
    _capability = await monitor.capability;
    await monitor.start();

    WidgetsBinding.instance.addObserver(this);
    _subscription = monitor.samples.listen(_onSample);

    final now = await monitor.current();
    if (now != null) _onSample(now);
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    await _subscription?.cancel();
    _subscription = null;
    _pending = null;
    _meterId = null;
    await ref.read(supplyMonitorProvider).stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground is the one moment the app is certainly alive on both
    // platforms, so it is worth a sample even if nothing changed.
    if (state == AppLifecycleState.resumed) unawaited(_sampleNow());
  }

  Future<void> _sampleNow() async {
    final sample = await ref.read(supplyMonitorProvider).current();
    if (sample != null) _onSample(sample);
  }

  Future<void> _onSample(PowerSample sample) async {
    final meterId = _meterId;
    if (meterId == null) return;

    final repo = ref.read(supplyRepositoryProvider);
    final open = await repo.ongoingForMeter(meterId);
    final observation =
        PowerObservation(charging: sample.charging, at: sample.at);

    final decision = ref.read(supplyInferenceEngineProvider).evaluate(
          observation: observation,
          capability: _capability,
          open: open,
          pending: _pending,
        );

    switch (decision) {
      case OpenFirst(:final state, :final at, :final capability):
        await repo.add(_event(meterId, state, at, capability));
        _pending = null;

      case Transition(:final closeAt, :final newState, :final capability):
        if (open != null) await repo.close(id: open.id, endedAt: closeAt);
        await repo.add(_event(meterId, newState, closeAt, capability));
        _pending = null;

      case NoChange():
        // Hold the candidate so the next sample can time how long it lasted.
        final differs = open != null &&
            (open.state == SupplyState.available) != sample.charging;
        _pending = differs ? (_pending ?? observation) : null;
    }
  }

  SupplyEvent _event(
    String meterId,
    SupplyState state,
    DateTime at,
    PlatformCapability capability,
  ) =>
      SupplyEvent(
        id: ref.read(uuidProvider).v7(),
        meterId: meterId,
        state: state,
        startedAt: at,
        source: SupplySource.inferredCharging,
        platformCapability: capability,
      );
}

final supplyInferenceControllerProvider =
    Provider<SupplyInferenceController>((ref) {
  final controller = SupplyInferenceController(ref);
  ref.onDispose(controller.stop);
  return controller;
});

/// Starts inference for whichever meter is selected, and follows a change.
final supplyInferenceProvider = Provider<void>((ref) {
  final meter = ref.watch(selectedMeterProvider);
  if (meter == null) return;
  unawaited(ref.watch(supplyInferenceControllerProvider).start(meter.id));
});
