import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/solar_sizing_engine.dart';
import 'package:grid/domain/value_objects/units.dart';

void main() {
  const engine = SolarSizingEngine();

  SolarSizing size({
    double daily = 10,
    double longest = 8,
    double mean = 6,
    int days = 30,
    double coverage = 0.9,
    Naira? spend,
  }) =>
      engine.size(
        dailyKwh: Kwh.fromDouble(daily),
        longestOutageHours: longest,
        meanOutageHoursPerDay: mean,
        daysMeasured: days,
        coverage: coverage,
        monthlyGeneratorSpend: spend,
      );

  group('refusals', () {
    test('too little history to size against', () {
      final r = size(days: 5) as SizingUnavailable;
      expect(r.reason, SizingGap.notEnoughConsumption);
      expect(r.detail, contains('5 days'));
    });

    test('thin supply coverage, because the battery is sized on outages', () {
      final r = size(coverage: 0.3) as SizingUnavailable;
      expect(r.reason, SizingGap.notEnoughSupply);
      expect(r.detail, contains('30%'));
    });

    test('a household with no real outages is told it does not need one', () {
      // The commercially convenient thing here is to size something anyway.
      final r = size(longest: 1.0) as SizingUnavailable;
      expect(r.reason, SizingGap.noMeaningfulOutages);
      expect(r.detail, contains('do not need'));
    });
  });

  group('sizing', () {
    test('the array replaces a day of measured consumption after losses', () {
      // 10 kWh / (4 sun hours * 0.75) = 3.33 kW.
      final s = size(daily: 10) as Sized;
      expect(s.panelKw, closeTo(3.3, 0.1));
    });

    test('the battery is sized on the longest outage, not the average', () {
      // The whole point: an average-sized battery is flat precisely on the
      // days the household bought it for.
      final onAverage = size(daily: 10, longest: 6, mean: 6) as Sized;
      final onWorst = size(daily: 10, longest: 14, mean: 6) as Sized;
      expect(onWorst.batteryKwh, greaterThan(onAverage.batteryKwh));

      // 10/24 kWh an hour * 14 hours / 0.8 depth of discharge = 7.3.
      expect(onWorst.batteryKwh, closeTo(7.3, 0.2));
    });

    test('storage allows for depth of discharge rather than sizing to zero',
        () {
      final s = size(daily: 24, longest: 10) as Sized;
      final naive = 1.0 * 10; // 1 kWh an hour for ten hours
      expect(s.batteryKwh, greaterThan(naive),
          reason: 'sizing to 100% DoD is how a bank dies in two years');
    });

    test('the inverter carries surge headroom', () {
      final s = size(daily: 24) as Sized;
      expect(s.inverterKw, closeTo(3.0, 0.1));
    });

    test('nothing is quoted to a precision its inputs do not have', () {
      final s = size(daily: 13.7, longest: 9.3) as Sized;
      expect((s.panelKw * 10) % 1, 0);
      expect((s.batteryKwh * 10) % 1, 0);
    });

    test('a short history is marked rough', () {
      expect((size(days: 20) as Sized).isRough, isTrue);
      expect((size(days: 60) as Sized).isRough, isFalse);
    });

    test('states what it does not know, as part of the result', () {
      final s = size() as Sized;
      expect(s.unknowns, isNotEmpty);
      expect(s.unknowns.join(' ').toLowerCase(), contains('shading'));
    });
  });

  group('payback', () {
    test('is absent without logged generator spend', () {
      // Inventing a fuel bill to produce a payback figure is exactly the
      // vendor behaviour this feature replaces.
      expect((size() as Sized).payback, isNull);
      expect((size(spend: Naira.zero) as Sized).payback, isNull);
    });

    test('is a range, and the low cost pays back sooner', () {
      final s = size(spend: Naira.fromNaira(40000)) as Sized;
      final p = s.payback!;
      expect(p.systemCostLow < p.systemCostHigh, isTrue);
      expect(p.monthsLow, lessThan(p.monthsHigh));
      expect(p.monthsLow, greaterThan(0));
    });

    test('the system costs millions, not tens of thousands', () {
      // An earlier version divided by 100 on top of `fromNaira` and priced a
      // 3.3 kW array with storage at ₦44,000, giving a two-month payback —
      // a figure a reader believes for as long as it takes to think about it.
      final p = (size(daily: 10, spend: Naira.fromNaira(40000)) as Sized)
          .payback!;
      expect(p.systemCostLow.value, greaterThan(2000000));
      expect(p.systemCostHigh.value, lessThan(12000000));
      expect(p.monthsLow, greaterThan(24),
          reason: 'a household system does not pay for itself in a year');
    });

    test('a bigger fuel bill pays back faster', () {
      final small = (size(spend: Naira.fromNaira(20000)) as Sized).payback!;
      final large = (size(spend: Naira.fromNaira(80000)) as Sized).payback!;
      expect(large.monthsLow, lessThan(small.monthsLow));
    });

    test('carries the measured spend it was computed from', () {
      final p = (size(spend: Naira.fromNaira(37500)) as Sized).payback!;
      expect(p.monthlyGeneratorSpend.value, closeTo(37500, 0.01));
    });
  });
}
