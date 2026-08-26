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

  group('the coach', () {
    const engine = LoadModelEngine();
    final rate = Rate.fromNaira(200);

    LoadModel modelOf({Kwh? measured}) => engine.model(
          appliances: [
            appliance(id: 'a1', name: 'Air conditioner', watts: 1200,
                hours: 6, quantity: 1),
            appliance(id: 'a2', name: 'Fridge', watts: 150, hours: 24,
                quantity: 1),
          ],
          supplyHoursPerDay: 24,
          measuredDailyTotal: measured,
        );

    test('prices every appliance for a month', () {
      final costs = engine.coach(model: modelOf(), rate: rate);
      expect(costs, hasLength(2));
      // AC: 1200 W * 6 h = 7.2 kWh a day, 216 a month, at 200 = 43,200.
      final ac = costs.firstWhere((c) => c.appliance.name.startsWith('Air'));
      expect(ac.monthlyCost.value, closeTo(43200, 50));
    });

    test('ranks the expensive one first, as the attribution does', () {
      final costs = engine.coach(model: modelOf(), rate: rate);
      expect(costs.first.appliance.name, 'Air conditioner');
      expect(costs.first.monthlyCost > costs.last.monthlyCost, isTrue);
    });

    test('pegs the figures to the meter, not to the inventory', () {
      // Modelled total is 10.8 kWh a day; the meter says 5.4. A coach that
      // quotes savings off the model would promise twice what switching
      // something off could actually deliver.
      final measured = engine.coach(
        model: modelOf(measured: Kwh.fromDouble(5.4)),
        rate: rate,
      );
      final unmeasured = engine.coach(model: modelOf(), rate: rate);

      expect(measured.first.normalisation, closeTo(0.5, 0.02));
      expect(
        measured.first.monthlyCost.kobo,
        closeTo(unmeasured.first.monthlyCost.kobo * 0.5, 2000),
      );
    });

    test('a what-if scales the saving by the hours given up', () {
      final ac = engine.coach(model: modelOf(), rate: rate).first;
      // Six hours down to four is a third of its running.
      expect(
        ac.savingFromRunningLess(2).kobo,
        closeTo(ac.monthlyCost.kobo / 3, 200),
      );
    });

    test('giving up more hours than it runs saves its cost, not more', () {
      final ac = engine.coach(model: modelOf(), rate: rate).first;
      expect(ac.savingFromRunningLess(50).kobo, ac.monthlyCost.kobo);
      expect(ac.savingFromRunningLess(0).kobo, 0);
    });

    test('an empty inventory coaches nothing rather than dividing by zero',
        () {
      final empty = engine.model(appliances: const [], supplyHoursPerDay: 24);
      expect(engine.coach(model: empty, rate: rate), isEmpty);
    });
  });
}
