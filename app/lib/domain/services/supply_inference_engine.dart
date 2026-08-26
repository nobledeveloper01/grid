import '../entities/supply_event.dart';
import '../value_objects/enums.dart';

/// A power-state observation, as the domain sees it.
///
/// Deliberately not the platform's `PowerSample` — the engine must not depend
/// on anything above it (ADR-0002).
class PowerObservation {
  const PowerObservation({required this.charging, required this.at});

  final bool charging;
  final DateTime at;
}

/// What the engine wants done as a result of an observation.
sealed class SupplyDecision {
  const SupplyDecision();
}

/// Nothing to do: the state has not settled, or has not changed.
final class NoChange extends SupplyDecision {
  const NoChange(this.reason);

  /// Why nothing happened, so the caller can log or explain it.
  final String reason;
}

/// Close the open event and start a new one in the opposite state.
final class Transition extends SupplyDecision {
  const Transition({
    required this.closeAt,
    required this.newState,
    required this.capability,
  });

  final DateTime closeAt;
  final SupplyState newState;
  final PlatformCapability capability;
}

/// There was no open event, so start one.
final class OpenFirst extends SupplyDecision {
  const OpenFirst({
    required this.state,
    required this.at,
    required this.capability,
  });

  final SupplyState state;
  final DateTime at;
  final PlatformCapability capability;
}

/// Turns charging-state observations into supply events.
///
/// The inference is deliberately conservative, because it is guessing. A
/// phone is on charge for reasons that have nothing to do with the mains
/// coming back — someone unplugged it to take a call, plugged it into a
/// laptop, moved it to a power bank. Every one of those looks identical to
/// the grid returning.
///
/// Three rules keep the guess honest:
///
/// 1. **Debounce.** A state has to hold for [settleTime] before it is
///    believed. This throws away cable jiggling and brief unplugging, which
///    is most of the noise.
/// 2. **Manual wins.** An event the user entered by hand is never overwritten
///    by inference; the caller supersedes rather than edits (ADR-0001).
/// 3. **The capability travels with the event.** Whatever the platform could
///    promise at the time is recorded on the row, so coverage can be reported
///    honestly across a period where it changed (ADR-0006).
///
/// Pure Dart. Deterministic for a given (observation, open event, capability).
class SupplyInferenceEngine {
  const SupplyInferenceEngine();

  /// How long a state must hold before it is believed.
  ///
  /// Three minutes filters cable disconnections and short trips without
  /// losing real outages — a genuine outage lasts far longer, and one that
  /// does not is not worth a row.
  static const Duration settleTime = Duration(minutes: 3);

  /// Beyond this, a sample says nothing about the time before it. A phone
  /// that was off for six hours cannot report what the grid did meanwhile,
  /// and the gap stays `unknown`.
  static const Duration staleAfter = Duration(minutes: 45);

  /// Decides what an observation means.
  ///
  /// [pending] is the last observation whose state differed from the open
  /// event — the candidate being debounced. Null when nothing is pending.
  SupplyDecision evaluate({
    required PowerObservation observation,
    required PlatformCapability capability,
    SupplyEvent? open,
    PowerObservation? pending,
  }) {
    final observed =
        observation.charging ? SupplyState.available : SupplyState.unavailable;

    if (open == null) {
      return OpenFirst(
        state: observed,
        at: observation.at,
        capability: capability,
      );
    }

    // A manual entry is the user's own account of what happened. Inference
    // does not get to argue with it.
    if (open.source == SupplySource.manual) {
      return const NoChange('the open period was entered by hand');
    }

    if (open.state == observed) {
      return const NoChange('state unchanged');
    }

    // The state differs. It has to hold before we believe it.
    if (pending == null) {
      return const NoChange('change seen, waiting for it to settle');
    }

    if (pending.charging != observation.charging) {
      return const NoChange('change did not hold, discarded');
    }

    final held = observation.at.difference(pending.at);
    if (held < settleTime) {
      return NoChange(
        'held for ${held.inSeconds}s, needs ${settleTime.inSeconds}s',
      );
    }

    // Believed. The period closes when the change was *first* seen, not when
    // it was confirmed — the power went off at the start of the gap, not at
    // the end of our debounce.
    return Transition(
      closeAt: pending.at,
      newState: observed,
      capability: capability,
    );
  }

  /// Whether a gap between two observations is too long to bridge.
  ///
  /// A gap that fails this must be left `unknown` rather than filled in with
  /// whichever state sat on either side of it. This is the single rule that
  /// keeps a dispute pack defensible.
  bool canBridge(DateTime from, DateTime to) =>
      to.difference(from).abs() <= staleAfter;
}
