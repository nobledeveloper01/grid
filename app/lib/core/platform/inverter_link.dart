import '../../domain/value_objects/units.dart';

/// Reading an inverter or charge controller over Bluetooth.
///
/// Phase 7. A household on an inverter has a second meter they never think of
/// as one: the controller already knows the battery's state of charge, what
/// the panels made today, and what the load drew. Grid asks it, so that
/// household stops being the one Grid cannot measure.
///
/// **The exit gate is about failure, not success.** Two dozen manufacturers
/// ship a dozen protocols, most undocumented, and Grid will never speak more
/// than a handful. So the contract here is that an unsupported controller
/// degrades to manual entry rather than to a dead screen — and the façade
/// exists to make that the default rather than an afterthought.
///
/// The BLE implementation itself needs hardware to write against and hardware
/// to verify. What ships today is the port, the null implementation, and the
/// fallback; `PlatformInverterLink` is the seam a real adapter drops into.
abstract interface class InverterLink {
  /// Whether this build can talk Bluetooth at all.
  ///
  /// False on a simulator, on a device with BLE off, and wherever permission
  /// was declined. Callers use it to decide whether to *offer* the scan, not
  /// to decide what to do when it fails.
  Future<bool> get isAvailable;

  /// Looks for controllers nearby.
  Future<List<InverterDevice>> scan({Duration timeout});

  /// Reads one sample, or explains why it could not.
  Future<InverterReading> read(InverterDevice device);
}

/// A controller Grid can see.
class InverterDevice {
  const InverterDevice({
    required this.id,
    required this.name,
    required this.protocol,
  });

  final String id;
  final String name;

  /// Null when Grid can see the device but does not recognise what it speaks.
  /// Surfaced rather than hidden: "found, not understood" is a different
  /// message from "nothing found", and it is the one that tells a user their
  /// hardware is simply not one of the supported ones.
  final InverterProtocol? protocol;

  bool get isSupported => protocol != null;
}

/// The protocols Grid speaks. Two, deliberately — the two most common
/// controllers in this market — rather than a long list half-implemented.
enum InverterProtocol {
  victronVeDirect('Victron VE.Direct'),
  renogyModbus('Renogy Modbus');

  const InverterProtocol(this.label);
  final String label;
}

sealed class InverterReading {
  const InverterReading();
}

class InverterSample extends InverterReading {
  const InverterSample({
    required this.stateOfCharge,
    required this.solarYieldToday,
    required this.loadToday,
    required this.readAt,
  });

  /// 0–1.
  final double stateOfCharge;

  final Kwh solarYieldToday;
  final Kwh loadToday;
  final DateTime readAt;
}

/// Why a read did not produce a sample, and what the user should do instead.
///
/// Every one of these carries a forward path, because the whole point of the
/// gate is that none of them is a dead end.
class InverterUnavailable extends InverterReading {
  const InverterUnavailable(this.reason, this.detail);

  final InverterGap reason;
  final String detail;

  /// True where typing the figure by hand is the sensible next step. That is
  /// all of them: there is no failure here that should leave a user stuck.
  bool get fallsBackToManual => true;
}

enum InverterGap {
  /// This build cannot do Bluetooth.
  noBluetooth,

  /// Nothing answered.
  nothingFound,

  /// Found, but Grid does not speak what it speaks.
  unsupportedProtocol,

  /// Spoke, then stopped.
  droppedMidRead,
}

/// Does nothing, and says so usefully.
///
/// Used in tests, on the simulator, and on any build without the BLE adapter
/// compiled in. Every call returns a result carrying a forward path rather
/// than throwing, so no screen needs a null check or a try block to stay
/// usable.
class NullInverterLink implements InverterLink {
  const NullInverterLink();

  @override
  Future<bool> get isAvailable async => false;

  @override
  Future<List<InverterDevice>> scan({Duration timeout = const Duration(seconds: 8)}) async =>
      const [];

  @override
  Future<InverterReading> read(InverterDevice device) async =>
      const InverterUnavailable(
        InverterGap.noBluetooth,
        'This phone cannot reach your inverter over Bluetooth. Type the '
        'figures from its screen instead — Grid treats them exactly the same.',
      );
}

/// Chooses the message for a gap. Kept out of the widgets so the wording is in
/// one place and can be checked by a test rather than by reading six screens.
String inverterGapMessage(InverterGap gap) => switch (gap) {
      InverterGap.noBluetooth =>
        'This phone cannot reach your inverter over Bluetooth. Type the '
            'figures from its screen instead — Grid treats them exactly the '
            'same.',
      InverterGap.nothingFound =>
        'Nothing answered. Check the controller is powered and within a few '
            'metres, or just type what its screen says.',
      InverterGap.unsupportedProtocol =>
        'Grid found your controller but does not speak its language. That is '
            'a limitation of Grid, not of your hardware — type the figures '
            'from its screen and nothing else changes.',
      InverterGap.droppedMidRead =>
        'The connection dropped part way through, so Grid has nothing it '
            'would stand behind. Try again, or type the figures instead.',
    };
