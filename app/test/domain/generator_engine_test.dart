import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/entities/generator.dart';
import 'package:grid/domain/services/generator_engine.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

Generator gen({
  String id = 'g1',
  double kva = 2.5,
  double lph = 1.0,
}) =>
    Generator(
      id: id,
      meterId: 'm1',
      name: 'Backup set',
      ratedKva: kva,
      litresPerHour: lph,
    );

GeneratorRun run({
  required String id,
  required int daysAgo,
  required double hours,
  String? generatorId,
}) {
  final start = now.subtract(Duration(days: daysAgo));
  return GeneratorRun(
    id: id,
    meterId: 'm1',
    startedAt: start,
    endedAt: start.add(Duration(minutes: (hours * 60).round())),
    generatorId: generatorId,
  );
}

FuelPurchase fuel({
  required String id,
  required int daysAgo,
  double litres = 10,
  double naira = 12000,
}) =>
    FuelPurchase(
      id: id,
      meterId: 'm1',
      litres: litres,
      amount: Naira.fromNaira(naira),
      purchasedAt: now.subtract(Duration(days: daysAgo)),
    );

void main() {
  const engine = GeneratorEngine();
  final from = now.subtract(const Duration(days: 30));

  GeneratorCost costOf({
    required List<GeneratorRun> runs,
    required List<FuelPurchase> fuels,
    List<Generator>? generators,
    DateTime? windowStart,
  }) =>
      engine.cost(
        runs: runs,
        fuel: fuels,
        generators: generators ?? [gen()],
        from: windowStart ?? from,
        to: now,
        now: now,
      );

  group('preconditions', () {
    test('too few runs says how many more are needed', () {
      final r = costOf(
        runs: [run(id: 'r1', daysAgo: 3, hours: 4)],
        fuels: [fuel(id: 'f1', daysAgo: 3)],
      ) as GeneratorCostUnknown;
      expect(r.reason, GeneratorGap.noRuns);
      expect(r.needed, 1);
    });

    test('runs without fuel cannot be priced', () {
      final r = costOf(
        runs: [
          run(id: 'r1', daysAgo: 3, hours: 4),
          run(id: 'r2', daysAgo: 5, hours: 4),
        ],
        fuels: const [],
      ) as GeneratorCostUnknown;
      expect(r.reason, GeneratorGap.noFuel);
    });

    test('no generator on record yields no modelled output', () {
      final r = costOf(
        runs: [
          run(id: 'r1', daysAgo: 3, hours: 4),
          run(id: 'r2', daysAgo: 5, hours: 4),
        ],
        fuels: [fuel(id: 'f1', daysAgo: 3)],
        generators: const [],
      );
      expect(r, isA<GeneratorCostUnknown>());
    });
  });

  group('the window', () {
    test('fuel outside the window is not divided by running inside it', () {
      // The trap: a month of fuel against a week of running gives a rate four
      // times too low, and it looks entirely reasonable on screen.
      final runs = [
        run(id: 'r1', daysAgo: 2, hours: 5),
        run(id: 'r2', daysAgo: 4, hours: 5),
      ];
      final wide = costOf(
        runs: runs,
        fuels: [
          fuel(id: 'f1', daysAgo: 2),
          fuel(id: 'f2', daysAgo: 25), // inside 30 days
        ],
      ) as GeneratorCostKnown;

      final narrow = engine.cost(
        runs: runs,
        fuel: [
          fuel(id: 'f1', daysAgo: 2),
          fuel(id: 'f2', daysAgo: 25),
        ],
        generators: [gen()],
        from: now.subtract(const Duration(days: 7)),
        to: now,
        now: now,
      ) as GeneratorCostKnown;

      expect(wide.litres, 20);
      expect(narrow.litres, 10, reason: 'the older purchase is out of window');
      expect(narrow.rate.koboPerKwh, lessThan(wide.rate.koboPerKwh));
    });
  });

  group('the rate', () {
    test('is spend over modelled output', () {
      // 2.5 kVA -> 2.5 * 0.8 * 0.8 = 1.6 kW delivered.
      // 10 hours -> 16 kWh. 24,000 naira -> 1,500/kWh.
      final r = costOf(
        runs: [
          run(id: 'r1', daysAgo: 2, hours: 5),
          run(id: 'r2', daysAgo: 4, hours: 5),
        ],
        fuels: [
          fuel(id: 'f1', daysAgo: 2, litres: 10, naira: 12000),
          fuel(id: 'f2', daysAgo: 4, litres: 10, naira: 12000),
        ],
      ) as GeneratorCostKnown;

      expect(r.hours, closeTo(10, 0.01));
      expect(r.energy.value, closeTo(16, 0.01));
      expect(r.rate.value, closeTo(1500, 1));
      expect(r.isRough, isTrue, reason: 'two runs is not a confident rate');
    });

    test('an hour of running has a price, which is the actual decision', () {
      final r = costOf(
        runs: [
          run(id: 'r1', daysAgo: 2, hours: 5),
          run(id: 'r2', daysAgo: 4, hours: 5),
        ],
        fuels: [fuel(id: 'f1', daysAgo: 2, litres: 20, naira: 24000)],
      ) as GeneratorCostKnown;
      expect(engine.costPerHour(cost: r).value, closeTo(2400, 1));
    });

    test('stops being rough once there is enough running to average', () {
      final r = costOf(
        runs: [
          for (var i = 1; i <= 6; i++)
            run(id: 'r$i', daysAgo: i * 2, hours: 3),
        ],
        fuels: [fuel(id: 'f1', daysAgo: 2, litres: 20, naira: 24000)],
      ) as GeneratorCostKnown;
      expect(r.isRough, isFalse);
    });
  });

  group('blended', () {
    BlendedCost blend({double gridKwh = 300, double gridNaira = 209.70}) {
      final generator = costOf(
        runs: [
          run(id: 'r1', daysAgo: 2, hours: 5),
          run(id: 'r2', daysAgo: 4, hours: 5),
        ],
        fuels: [fuel(id: 'f1', daysAgo: 2, litres: 20, naira: 24000)],
      ) as GeneratorCostKnown;

      return engine.blend(
        gridEnergy: Kwh.fromDouble(gridKwh),
        gridRate: Rate.fromNaira(gridNaira),
        generator: generator,
      );
    }

    test('states the household total across both sources', () {
      final b = blend();
      expect(b.totalEnergy.value, closeTo(316, 0.1));
      // 300 kWh at 209.70 = 62,910, plus 24,000 of fuel.
      expect(b.totalSpend.value, closeTo(86910, 5));
    });

    test('the blended rate sits between the two', () {
      final b = blend();
      expect(b.blendedRate.value, greaterThan(b.gridRate.value));
      expect(b.blendedRate.value, lessThan(b.generatorRate.value));
    });

    test('says how many times more a generated unit costs', () {
      final b = blend();
      // 1,500 against 209.70 — around seven times.
      expect(b.multiple, closeTo(7.15, 0.2));
    });

    test('a zero grid rate yields no multiple rather than infinity', () {
      final b = blend(gridNaira: 0);
      expect(b.multiple, isNull);
    });

    test('reports the share that came off the generator', () {
      final b = blend();
      expect(b.generatorShare, closeTo(16 / 316, 0.001));
    });
  });
}
