import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/services/band_adherence_engine.dart';
import 'package:grid/domain/services/compliance_engine.dart';
import 'package:grid/domain/value_objects/enums.dart';
import 'package:grid/domain/value_objects/units.dart';

import '_fixtures.dart';

/// Band A is billed at 225/kWh, and each band below it costs less. These are
/// stand-ins for the bundled table, not the gazetted figures — the engine is
/// under test, not the tariff.
final _rates = {
  TariffBand.a: Rate.fromNaira(225),
  TariffBand.b: Rate.fromNaira(160),
  TariffBand.c: Rate.fromNaira(90),
  TariffBand.d: Rate.fromNaira(66),
  TariffBand.e: Rate.fromNaira(55),
};

Rate? _rateFor(TariffBand b) => _rates[b];

/// A summary with the numbers stated directly, so a test says what it means
/// rather than constructing thirty days of events to imply it.
SupplySummary summary({
  required double hours,
  required double coverage,
  required int usableDays,
}) =>
    SupplySummary(
      days: const [],
      rollingAverageHours: hours,
      coverage: coverage,
      usableDayCount: usableDays,
    );

void main() {
  const engine = BandAdherenceEngine();

  group('bandFor', () {
    test('returns the highest band the delivered hours qualify for', () {
      expect(BandAdherenceEngine.bandFor(21), TariffBand.a);
      expect(BandAdherenceEngine.bandFor(20), TariffBand.a);
      expect(BandAdherenceEngine.bandFor(19.9), TariffBand.b);
      expect(BandAdherenceEngine.bandFor(12), TariffBand.c);
      expect(BandAdherenceEngine.bandFor(11.4), TariffBand.d);
      expect(BandAdherenceEngine.bandFor(4), TariffBand.e);
    });

    test('returns null below the lowest band rather than rounding up', () {
      expect(BandAdherenceEngine.bandFor(3.9), isNull);
      expect(BandAdherenceEngine.bandFor(0), isNull);
    });
  });

  group('evidence floors', () {
    test('too few usable days yields Unknown, not an average', () {
      final r = engine.evaluate(
        billedBand: TariffBand.a,
        summary: summary(hours: 6, coverage: 0.95, usableDays: 6),
        energy: Kwh.fromDouble(300),
        billedRate: _rates[TariffBand.a]!,
        rateForBand: _rateFor,
      );
      expect(r, isA<AdherenceUnknown>());
      expect((r as AdherenceUnknown).reason, AdherenceGap.tooFewUsableDays);
    });

    test('low coverage yields Unknown even with a large apparent shortfall',
        () {
      // The trap this exists for: 6 hours against a 20-hour commitment is a
      // dramatic figure, and reporting it off 40% coverage would be the most
      // damaging thing this engine could do.
      final r = engine.evaluate(
        billedBand: TariffBand.a,
        summary: summary(hours: 6, coverage: 0.40, usableDays: 20),
        energy: Kwh.fromDouble(300),
        billedRate: _rates[TariffBand.a]!,
        rateForBand: _rateFor,
      );
      expect(r, isA<AdherenceUnknown>());
      expect((r as AdherenceUnknown).reason, AdherenceGap.coverageTooLow);
    });

    test('the coverage floor matches the compliance engine exactly', () {
      // Two engines with two thresholds would put two different answers on
      // two screens of the same app.
      expect(BandAdherenceEngine.minimumCoverage,
          ComplianceEngine.minimumWindowCoverage);
      expect(BandAdherenceEngine.materialShortfall,
          ComplianceEngine.breachThreshold);
    });
  });

  group('met', () {
    test('delivery above the commitment reports a surplus', () {
      final r = engine.evaluate(
        billedBand: TariffBand.b,
        summary: summary(hours: 17.5, coverage: 0.9, usableDays: 28),
        energy: Kwh.fromDouble(200),
        billedRate: _rates[TariffBand.b]!,
        rateForBand: _rateFor,
      );
      expect(r, isA<AdherenceMet>());
      expect((r as AdherenceMet).surplusHours, closeTo(1.5, 1e-9));
    });

    test('a shortfall inside the noise threshold is not a case', () {
      // 18.5 against 20 is 7.5% short — below the 10% materiality floor.
      final r = engine.evaluate(
        billedBand: TariffBand.a,
        summary: summary(hours: 18.5, coverage: 0.9, usableDays: 28),
        energy: Kwh.fromDouble(200),
        billedRate: _rates[TariffBand.a]!,
        rateForBand: _rateFor,
      );
      expect(r, isA<AdherenceMet>());
    });
  });

  group('shortfall', () {
    AdherenceShortfall shortfallAt(double hours, {double energy = 300}) {
      final r = engine.evaluate(
        billedBand: TariffBand.a,
        summary: summary(hours: hours, coverage: 0.88, usableDays: 27),
        energy: Kwh.fromDouble(energy),
        billedRate: _rates[TariffBand.a]!,
        rateForBand: _rateFor,
      );
      return r as AdherenceShortfall;
    }

    test('reports hours, percent and the band actually delivered', () {
      final r = shortfallAt(11.4);
      expect(r.shortfallHours, closeTo(8.6, 1e-9));
      expect(r.shortfallPercent, closeTo(0.43, 0.005));
      expect(r.deliveredBand, TariffBand.d);
      expect(r.isBelowLowestBand, isFalse);
    });

    test('values the shortfall as energy times the rate difference', () {
      // 300 kWh at (225 - 66) = 159/kWh.
      final r = shortfallAt(11.4, energy: 300);
      expect(r.deliveredRate, _rates[TariffBand.d]);
      expect(r.overpayment!.kobo, Naira.fromNaira(300 * 159).kobo);
    });

    test('the valuation is exact in kobo, not nearly', () {
      // 0.1 + 0.2 arithmetic in naira would drift; integers do not.
      final r = shortfallAt(11.4, energy: 33.333);
      final expected =
          Rate.fromNaira(159).costOf(Kwh.fromDouble(33.333)).kobo;
      expect(r.overpayment!.kobo, expected);
    });

    test('below the lowest band it says so rather than rounding into E', () {
      final r = shortfallAt(2.5);
      expect(r.deliveredBand, isNull);
      expect(r.isBelowLowestBand, isTrue);
      expect(r.deliveredRate, isNull);
      expect(r.overpayment, isNull,
          reason: 'no band means no rate, and no rate means no claim');
    });

    test('a missing rate for the delivered band yields no valuation', () {
      final r = engine.evaluate(
        billedBand: TariffBand.a,
        summary: summary(hours: 11.4, coverage: 0.88, usableDays: 27),
        energy: Kwh.fromDouble(300),
        billedRate: _rates[TariffBand.a]!,
        rateForBand: (_) => null,
      ) as AdherenceShortfall;
      expect(r.overpayment, isNull);
      expect(r.shortfallHours, closeTo(8.6, 1e-9),
          reason: 'the hours are still measured even when the money is not');
    });

    test('a delivered rate above the billed rate yields no overpayment', () {
      // Nonsensical in practice, but the engine must not report a negative
      // amount as though the user were owed money the other way.
      final r = engine.evaluate(
        billedBand: TariffBand.a,
        summary: summary(hours: 11.4, coverage: 0.88, usableDays: 27),
        energy: Kwh.fromDouble(300),
        billedRate: Rate.fromNaira(50),
        rateForBand: _rateFor,
      ) as AdherenceShortfall;
      expect(r.overpayment, isNull);
    });

    test('zero consumption yields a zero valuation, not a null one', () {
      final r = shortfallAt(11.4, energy: 0);
      expect(r.overpayment, isNotNull);
      expect(r.overpayment!.isZero, isTrue,
          reason: 'the shortfall is still real; it just cost nothing');
    });
  });

  group('against a real summary from the compliance engine', () {
    test('a month of eight-hour days on band A is valued end to end', () {
      const compliance = ComplianceEngine();
      final events = <dynamic>[];
      // 28 days, power on 08:00-16:00, off the rest. Fully covered.
      for (var d = 28; d >= 1; d--) {
        final dayStart = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: d));
        events.add(supply(
          id: 'off-$d',
          state: SupplyState.unavailable,
          from: dayStart,
          to: dayStart.add(const Duration(hours: 8)),
        ));
        events.add(supply(
          id: 'on-$d',
          state: SupplyState.available,
          from: dayStart.add(const Duration(hours: 8)),
          to: dayStart.add(const Duration(hours: 16)),
        ));
        events.add(supply(
          id: 'off2-$d',
          state: SupplyState.unavailable,
          from: dayStart.add(const Duration(hours: 16)),
          to: dayStart.add(const Duration(hours: 24)),
        ));
      }

      final s = compliance.summarise(
        events: events.cast(),
        windowStart: now.subtract(const Duration(days: 29)),
        windowEnd: now,
        now: now,
      );

      final r = engine.evaluate(
        billedBand: TariffBand.a,
        summary: s,
        energy: Kwh.fromDouble(240),
        billedRate: _rates[TariffBand.a]!,
        rateForBand: _rateFor,
      );

      expect(r, isA<AdherenceShortfall>());
      final short = r as AdherenceShortfall;
      expect(short.measuredHours, closeTo(8, 0.01));
      expect(short.deliveredBand, TariffBand.d);
      expect(short.overpayment!.kobo,
          Naira.fromNaira(240 * (225 - 66)).kobo);
    });
  });
}
