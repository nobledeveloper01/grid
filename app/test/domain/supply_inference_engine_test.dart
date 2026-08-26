import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/supply_inference_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';

import '_fixtures.dart';

void main() {
  const engine = SupplyInferenceEngine();

  PowerObservation obs(bool charging, {Duration offset = Duration.zero}) =>
      PowerObservation(charging: charging, at: now.add(offset));

  group('the first observation', () {
    test('opens a period, since there is nothing to compare against', () {
      final decision = engine.evaluate(
        observation: obs(true),
        capability: PlatformCapability.continuous,
      );
      expect(decision, isA<OpenFirst>());
      final open = decision as OpenFirst;
      expect(open.state, SupplyState.available);
      expect(open.capability, PlatformCapability.continuous);
    });

    test('opens as unavailable when the device is not charging', () {
      final decision = engine.evaluate(
        observation: obs(false),
        capability: PlatformCapability.periodic,
      ) as OpenFirst;
      expect(decision.state, SupplyState.unavailable);
    });
  });

  group('a manual period', () {
    test('is never overwritten by inference', () {
      // The user said the power was off. A phone on charge does not get to
      // argue with that — they might be on a generator or a power bank.
      final decision = engine.evaluate(
        observation: obs(true),
        capability: PlatformCapability.continuous,
        open: supply(
          id: 'manual',
          state: SupplyState.unavailable,
          from: now.subtract(const Duration(hours: 2)),
          source: SupplySource.manual,
        ),
        pending: obs(true, offset: -const Duration(minutes: 30)),
      );
      expect(decision, isA<NoChange>());
      expect((decision as NoChange).reason, contains('by hand'));
    });
  });

  group('debounce', () {
    final inferredOn = supply(
      id: 'on',
      state: SupplyState.available,
      from: now.subtract(const Duration(hours: 3)),
      source: SupplySource.inferredCharging,
    );

    test('does nothing while the state is unchanged', () {
      final decision = engine.evaluate(
        observation: obs(true),
        capability: PlatformCapability.continuous,
        open: inferredOn,
      );
      expect(decision, isA<NoChange>());
      expect((decision as NoChange).reason, 'state unchanged');
    });

    test('waits when a change is first seen', () {
      final decision = engine.evaluate(
        observation: obs(false),
        capability: PlatformCapability.continuous,
        open: inferredOn,
      );
      expect(decision, isA<NoChange>());
      expect((decision as NoChange).reason, contains('settle'));
    });

    test('discards a change that does not hold', () {
      // Unplugged to take a call, plugged back in. Not an outage.
      final decision = engine.evaluate(
        observation: obs(true, offset: const Duration(minutes: 1)),
        capability: PlatformCapability.continuous,
        open: inferredOn,
        pending: obs(false),
      );
      expect(decision, isA<NoChange>());
    });

    test('still waits when the change has not held long enough', () {
      final decision = engine.evaluate(
        observation: obs(false, offset: const Duration(minutes: 2)),
        capability: PlatformCapability.continuous,
        open: inferredOn,
        pending: obs(false),
      );
      expect(decision, isA<NoChange>());
      expect((decision as NoChange).reason, contains('needs'));
    });

    test('believes a change that holds past the settle time', () {
      final decision = engine.evaluate(
        observation: obs(false, offset: const Duration(minutes: 4)),
        capability: PlatformCapability.continuous,
        open: inferredOn,
        pending: obs(false),
      );
      expect(decision, isA<Transition>());
      expect((decision as Transition).newState, SupplyState.unavailable);
    });

    test('closes the period when the change was first seen, not when confirmed',
        () {
      // The power went off at the start of the gap. Recording the moment we
      // finished debouncing would credit the user with three minutes of
      // supply they did not have.
      final firstSeen = obs(false);
      final decision = engine.evaluate(
        observation: obs(false, offset: const Duration(minutes: 5)),
        capability: PlatformCapability.continuous,
        open: inferredOn,
        pending: firstSeen,
      ) as Transition;
      expect(decision.closeAt, firstSeen.at);
    });

    test('the settle time is exactly the boundary, not approximately', () {
      final atBoundary = engine.evaluate(
        observation: obs(false, offset: SupplyInferenceEngine.settleTime),
        capability: PlatformCapability.continuous,
        open: inferredOn,
        pending: obs(false),
      );
      final justUnder = engine.evaluate(
        observation: obs(
          false,
          offset: SupplyInferenceEngine.settleTime - const Duration(seconds: 1),
        ),
        capability: PlatformCapability.continuous,
        open: inferredOn,
        pending: obs(false),
      );
      expect(atBoundary, isA<Transition>());
      expect(justUnder, isA<NoChange>());
    });
  });

  group('the capability travels with the event', () {
    test('is recorded on a transition', () {
      for (final capability in PlatformCapability.values) {
        final decision = engine.evaluate(
          observation: obs(false, offset: const Duration(minutes: 5)),
          capability: capability,
          open: supply(
            id: 'on',
            state: SupplyState.available,
            from: now.subtract(const Duration(hours: 3)),
            source: SupplySource.inferredCharging,
          ),
          pending: obs(false),
        ) as Transition;
        expect(decision.capability, capability);
      }
    });
  });

  group('bridging a gap', () {
    test('accepts a gap inside the staleness window', () {
      expect(
        engine.canBridge(now, now.add(const Duration(minutes: 30))),
        isTrue,
      );
    });

    test('refuses a gap the device cannot vouch for', () {
      // The phone was off for six hours. It has nothing to say about what
      // the grid did meanwhile, and the timeline must show that.
      expect(
        engine.canBridge(now, now.add(const Duration(hours: 6))),
        isFalse,
      );
    });

    test('is symmetric', () {
      final later = now.add(const Duration(hours: 6));
      expect(engine.canBridge(later, now), engine.canBridge(now, later));
    });

    test('the staleness boundary is exact', () {
      expect(
        engine.canBridge(now, now.add(SupplyInferenceEngine.staleAfter)),
        isTrue,
      );
      expect(
        engine.canBridge(
          now,
          now.add(SupplyInferenceEngine.staleAfter + const Duration(seconds: 1)),
        ),
        isFalse,
      );
    });
  });
}
