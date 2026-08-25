import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/load_model_engine.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  const engine = LoadModelEngine();

  group('empty inventory', () {
    test('models nothing without pretending to', () {
      final m = engine.model(appliances: const [], supplyHoursPerDay: 20);
      expect(m.modelledDailyTotal, Kwh.zero);
      expect(m.attributions, isEmpty);
      expect(m.divergence, isNull);
      expect(m.needsReconciliation, isFalse);
    });
  });

  group('modelling', () {
    test('computes watts x quantity x hours', () {
      // 1.5HP AC ~ 1100W for 8h = 8.8 kWh
      final m = engine.model(
        appliances: [appliance(id: 'a', name: 'AC', watts: 1100, hours: 8)],
        supplyHoursPerDay: 24,
      );
      expect(m.modelledDailyTotal.value, closeTo(8.8, 0.01));
    });

    test('multiplies by quantity', () {
      final m = engine.model(
        appliances: [
          appliance(id: 'f', name: 'Fan', watts: 75, quantity: 4, hours: 10),
        ],
        supplyHoursPerDay: 24,
      );
      expect(m.modelledDailyTotal.value, closeTo(3.0, 0.01));
    });

    test('caps mains-only appliances at measured supply hours', () {
      // A freezer cannot run 24h on grid power that was only there for 11.
      final m = engine.model(
        appliances: [
          appliance(id: 'z', name: 'Freezer', watts: 200, hours: 24),
        ],
        supplyHoursPerDay: 11,
      );
      expect(m.modelledDailyTotal.value, closeTo(2.2, 0.01));
    });

    test('does not cap appliances marked as not mains-only', () {
      final m = engine.model(
        appliances: [
          appliance(
            id: 'z',
            name: 'Inverter fridge',
            watts: 200,
            hours: 24,
            mainsOnly: false,
          ),
        ],
        supplyHoursPerDay: 11,
      );
      expect(m.modelledDailyTotal.value, closeTo(4.8, 0.01));
    });

    test('orders attributions by size, largest first', () {
      final m = engine.model(
        appliances: [
          appliance(id: 'b', name: 'Bulb', watts: 10, quantity: 6, hours: 6),
          appliance(id: 'a', name: 'AC', watts: 1100, hours: 8),
          appliance(id: 'f', name: 'Fan', watts: 75, quantity: 2, hours: 12),
        ],
        supplyHoursPerDay: 24,
      );
      expect(m.attributions.first.appliance.name, 'AC');
      expect(m.attributions.last.appliance.name, 'Bulb');
    });

    test('shares sum to one', () {
      final m = engine.model(
        appliances: [
          appliance(id: 'a', name: 'AC', watts: 1100, hours: 8),
          appliance(id: 'f', name: 'Fan', watts: 75, quantity: 2, hours: 12),
          appliance(id: 'b', name: 'Bulb', watts: 10, quantity: 6, hours: 6),
        ],
        supplyHoursPerDay: 24,
      );
      final sum = m.attributions.fold<double>(0, (a, x) => a + x.share);
      expect(sum, closeTo(1.0, 1e-9));
    });
  });

  group('reconciliation against measurement', () {
    test('agrees when the model matches the meter', () {
      final m = engine.model(
        appliances: [appliance(id: 'a', name: 'AC', watts: 1000, hours: 10)],
        supplyHoursPerDay: 24,
        measuredDailyTotal: Kwh.fromDouble(10),
      );
      expect(m.divergence, closeTo(0, 0.01));
      expect(m.needsReconciliation, isFalse);
    });

    test('detects unaccounted load when the meter saw more than the model', () {
      final m = engine.model(
        appliances: [appliance(id: 'a', name: 'AC', watts: 1000, hours: 5)],
        supplyHoursPerDay: 24,
        measuredDailyTotal: Kwh.fromDouble(20),
      );
      expect(m.needsReconciliation, isTrue);
      expect(m.hasUnaccountedLoad, isTrue);
      expect(m.divergence!, lessThan(0));
    });

    test('detects an over-claiming model', () {
      final m = engine.model(
        appliances: [appliance(id: 'a', name: 'AC', watts: 2000, hours: 12)],
        supplyHoursPerDay: 24,
        measuredDailyTotal: Kwh.fromDouble(10),
      );
      expect(m.needsReconciliation, isTrue);
      expect(m.hasUnaccountedLoad, isFalse);
      expect(m.divergence!, greaterThan(0));
    });

    test('a zero measurement yields no divergence rather than infinity', () {
      final m = engine.model(
        appliances: [appliance(id: 'a', name: 'AC', watts: 1000, hours: 5)],
        supplyHoursPerDay: 24,
        measuredDailyTotal: Kwh.zero,
      );
      expect(m.divergence, isNull);
    });
  });

  group('normalisation', () {
    test('scales modelled shares onto the measured total', () {
      final m = engine.model(
        appliances: [
          appliance(id: 'a', name: 'AC', watts: 1000, hours: 10),
          appliance(id: 'f', name: 'Fan', watts: 100, hours: 10),
        ],
        supplyHoursPerDay: 24,
        measuredDailyTotal: Kwh.fromDouble(22),
      );
      final factor = engine.normalisationFactor(m);
      expect(factor, closeTo(2.0, 0.01));

      final acShare = m.attributions.first.normalisedShare(factor);
      // AC is ~91% of an 11 kWh model; normalised onto 22 kWh measured that
      // is ~182% — which is exactly the signal that the model is too small.
      expect(acShare, greaterThan(1.0));
    });

    test('is the identity when there is no measurement', () {
      final m = engine.model(
        appliances: [appliance(id: 'a', name: 'AC', watts: 1000, hours: 10)],
        supplyHoursPerDay: 24,
      );
      expect(engine.normalisationFactor(m), 1);
    });
  });
}
