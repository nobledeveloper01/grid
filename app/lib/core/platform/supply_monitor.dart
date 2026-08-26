import 'package:flutter/services.dart';

import '../../domain/value_objects/enums.dart';

/// One observation of the device's power state.
class PowerSample {
  const PowerSample({
    required this.charging,
    required this.at,
    required this.batteryPercent,
  });

  final bool charging;
  final DateTime at;
  final int batteryPercent;
}

/// Device power monitoring, behind one interface.
///
/// The two platforms differ so much here that pretending otherwise would be
/// dishonest, so the interface makes the difference explicit rather than
/// hiding it: [capability] says what this platform can actually promise, and
/// every recorded event carries that answer with it (ADR-0006).
abstract interface class SupplyMonitor {
  /// What this platform can promise. Android with a foreground service is
  /// `continuous`; Android without, and iOS at all, are `periodic`.
  Future<PlatformCapability> get capability;

  /// Samples as they arrive. Sparse by nature — this is not a stream you can
  /// assume is complete, which is the whole reason `unknown` exists.
  Stream<PowerSample> get samples;

  /// The state right now, for sampling on foreground.
  Future<PowerSample?> current();

  Future<void> start();
  Future<void> stop();
}

/// Talks to the native side over a method channel and an event channel.
class PlatformSupplyMonitor implements SupplyMonitor {
  PlatformSupplyMonitor({
    this.methods = const MethodChannel('grid/supply_monitor'),
    this.events = const EventChannel('grid/supply_monitor/samples'),
  });

  final MethodChannel methods;
  final EventChannel events;

  Stream<PowerSample>? _samples;

  @override
  Future<PlatformCapability> get capability async {
    try {
      final name = await methods.invokeMethod<String>('capability');
      if (name == null) return PlatformCapability.foregroundOnly;
      return PlatformCapability.values.byName(name);
    } on PlatformException {
      return PlatformCapability.foregroundOnly;
    } on MissingPluginException {
      return PlatformCapability.foregroundOnly;
    } on ArgumentError {
      // An unknown name from the native side is a bug, but not one worth
      // breaking the timeline over. Assume the weakest promise.
      return PlatformCapability.foregroundOnly;
    }
  }

  @override
  Stream<PowerSample> get samples => _samples ??= events
      .receiveBroadcastStream()
      .map(_decode)
      .where((s) => s != null)
      .cast<PowerSample>();

  @override
  Future<PowerSample?> current() async {
    try {
      final raw = await methods.invokeMethod<Map<dynamic, dynamic>>('current');
      return raw == null ? null : _decode(raw);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<void> start() async {
    try {
      await methods.invokeMethod<void>('start');
    } on PlatformException {
      // Starting is best-effort on both platforms. A refusal means less
      // coverage, not a broken app.
    } on MissingPluginException {
      // No native side registered.
    }
  }

  @override
  Future<void> stop() async {
    try {
      await methods.invokeMethod<void>('stop');
    } on PlatformException {
      // Ignore.
    } on MissingPluginException {
      // Ignore.
    }
  }

  static PowerSample? _decode(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<String, dynamic>();
    final at = map['at'];
    if (at is! int) return null;
    return PowerSample(
      charging: map['charging'] as bool? ?? false,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      batteryPercent: (map['battery'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Used where no native side is wired up, and on any platform that cannot
/// observe power state. Reports `foregroundOnly` and emits nothing, so the
/// timeline stays honestly empty rather than quietly fabricated.
class NullSupplyMonitor implements SupplyMonitor {
  const NullSupplyMonitor();

  @override
  Future<PlatformCapability> get capability async =>
      PlatformCapability.foregroundOnly;

  @override
  Stream<PowerSample> get samples => const Stream.empty();

  @override
  Future<PowerSample?> current() async => null;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}
}
