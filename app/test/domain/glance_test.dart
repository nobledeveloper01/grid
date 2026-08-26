import 'package:flutter_test/flutter_test.dart';
import 'package:grid/core/platform/glance_store.dart';
import 'package:grid/domain/services/forecast_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

void main() {
  const builder = GlanceBuilder();

  BalanceKnown balance(DateTime depletesOn, {int readings = 8}) => BalanceKnown(
        balance: Kwh.fromDouble(40),
        dailyMean: 8,
        depletesOn: depletesOn,
        daysRemaining: depletesOn.difference(now).inHours / 24,
        confidenceDays: readings < 4 ? 3 : 1,
        readingCount: readings,
      );

  CostProjected cost(double naira, {int daysOfData = 20}) => CostProjected(
        consumedSoFar: Kwh.fromDouble(200),
        projectedKwh: Kwh.fromDouble(310),
        projectedCost: Naira.fromNaira(naira),
        lowCost: Naira.fromNaira(naira * 0.9),
        highCost: Naira.fromNaira(naira * 1.1),
        rate: Rate.fromNaira(209.7),
        daysOfData: daysOfData,
        dailyMean: 10,
        cycleEnd: now.add(const Duration(days: 5)),
      );

  Glance prepaid(BalanceForecast? f) => builder.build(
        meterLabel: 'Home',
        isPrepaid: true,
        balance: f,
        cost: null,
        supply: SupplyState.available,
        now: now,
      );

  Glance postpaid(CostProjection? c) => builder.build(
        meterLabel: 'Home',
        isPrepaid: false,
        balance: null,
        cost: c,
        supply: SupplyState.unavailable,
        now: now,
      );

  group('days remaining', () {
    test('rounds down, because rounding up sends somebody to bed short', () {
      // 3.9 days left shown as "3" is safe. Shown as "4" it sends somebody to
      // bed on units that run out overnight.
      final g = prepaid(balance(now.add(const Duration(hours: 93))));
      expect(g.headline, '3 days');
    });

    test('one day is singular', () {
      expect(prepaid(balance(now.add(const Duration(hours: 30)))).headline,
          '1 day');
    });

    test('less than a day is zero, not negative or blank', () {
      expect(prepaid(balance(now.add(const Duration(hours: 5)))).headline,
          '0 days');
    });

    test('an already-passed date is zero, not a negative count', () {
      expect(prepaid(balance(now.subtract(const Duration(days: 2)))).headline,
          '0 days');
    });
  });

  group('what it will not claim', () {
    test('no forecast means a dash and an instruction, not a guess', () {
      final g = prepaid(const BalanceUnavailable(
          ForecastUnavailableReason.notEnoughReadings, 2));
      expect(g.headline, '—');
      expect(g.detail, contains('log a reading'));
      expect(g.isEstimate, isFalse);
    });

    test('a thin forecast is marked as an estimate', () {
      // The measured/modelled rule does not stop at the edge of the app.
      final g = prepaid(
          balance(now.add(const Duration(days: 6)), readings: 3));
      expect(g.isEstimate, isTrue);
      expect(g.detail, contains('roughly'));
    });

    test('a solid forecast is not marked', () {
      expect(prepaid(balance(now.add(const Duration(days: 6)))).isEstimate,
          isFalse);
    });

    test('a thin bill projection is marked too', () {
      expect(postpaid(cost(65000, daysOfData: 4)).isEstimate, isTrue);
      expect(postpaid(cost(65000)).isEstimate, isFalse);
    });
  });

  group('the postpaid glance', () {
    test('shows the whole-cycle bill, already formatted', () {
      // Formatted here, not in the widget: two implementations of naira
      // rendering is how the sign ends up orphaned in one of them.
      final g = postpaid(cost(65098));
      expect(g.headline, '${Naira.naira}65,098');
      expect(g.detail, 'this month');
    });

    test('carries supply state, so the widget need not use colour alone', () {
      expect(postpaid(cost(1000)).supply, SupplyState.unavailable);
      expect(prepaid(balance(now.add(const Duration(days: 4)))).supply,
          SupplyState.available);
    });
  });

  group('staleness', () {
    test('a fresh snapshot is not stale', () {
      final g = prepaid(balance(now.add(const Duration(days: 4))));
      expect(g.isStale(now.add(const Duration(hours: 2))), isFalse);
    });

    test('yesterday\'s figure is stale, and says so rather than passing as '
        'current', () {
      // A widget showing yesterday's depletion date as though it were
      // today's is a figure presented with more confidence than its
      // provenance supports — the same failure as interpolating supply.
      final g = prepaid(balance(now.add(const Duration(days: 4))));
      expect(g.isStale(now.add(const Duration(hours: 13))), isTrue);
    });
  });

  group('the snapshot', () {
    test('survives a round trip', () {
      final original = postpaid(cost(65098));
      final restored = Glance.fromJson(_encode(original));

      expect(restored, isNotNull);
      expect(restored!.headline, original.headline);
      expect(restored.supply, original.supply);
      expect(restored.isEstimate, original.isEstimate);
      expect(restored.updatedAt.toIso8601String(),
          original.updatedAt.toIso8601String());
    });

    test('anything unreadable is a quiet nothing, never a throw', () {
      // A widget that crashes is a blank rectangle on somebody's home screen
      // with no way to report itself.
      for (final bad in <String?>[
        null,
        '',
        'not json',
        '[]',
        '{}',
        '{"v":99,"headline":"x"}',
        '{"v":1}',
        '{"v":1,"updatedAt":"not a date"}',
      ]) {
        expect(Glance.fromJson(bad), isNull, reason: 'input: $bad');
      }
    });

    test('an unknown supply state falls back rather than failing', () {
      final json = _encode(postpaid(cost(1000)))
          .replaceFirst('"unavailable"', '"something-new"');
      expect(Glance.fromJson(json)?.supply, SupplyState.unknown);
    });
  });

  group('the null store', () {
    test('never throws, and reads back nothing', () async {
      const store = NullGlanceStore();
      await store.write(prepaid(balance(now.add(const Duration(days: 3)))));
      expect(await store.read(), isNull);
      await store.clear();
    });
  });

  test('both platforms agree on where the snapshot lives', () {
    // Written once here rather than in two native files, so a rename cannot
    // silently break one platform.
    expect(glanceStorageKey, 'grid.glance.v1');
    expect(glanceAppGroup, startsWith('group.'));
  });
}

String _encode(Glance g) =>
    '{"v":1,"meter":"${g.meterLabel}","headline":"${g.headline}",'
    '"detail":"${g.detail}","supply":"${g.supply.name}",'
    '"estimate":${g.isEstimate},'
    '"updatedAt":"${g.updatedAt.toIso8601String()}"}';
