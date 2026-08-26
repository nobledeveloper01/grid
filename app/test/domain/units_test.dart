import 'package:flutter_test/flutter_test.dart';
import 'package:grid/domain/value_objects/units.dart';

void main() {
  group('Kwh', () {
    test('round-trips through milli without drift', () {
      expect(Kwh.fromDouble(123.456).milli, 123456);
      expect(Kwh.fromDouble(123.456).value, closeTo(123.456, 1e-9));
    });

    test('arithmetic stays exact in integer space', () {
      final a = Kwh.fromDouble(0.1);
      final b = Kwh.fromDouble(0.2);
      // The classic float trap: 0.1 + 0.2 != 0.3. Integers make it exact.
      expect((a + b).milli, Kwh.fromDouble(0.3).milli);
    });

    test('comparisons work', () {
      expect(Kwh.fromDouble(5) > Kwh.fromDouble(4), isTrue);
      expect(Kwh.fromDouble(4) <= Kwh.fromDouble(4), isTrue);
      expect((Kwh.fromDouble(3) - Kwh.fromDouble(5)).isNegative, isTrue);
    });

    test('formats to one decimal place', () {
      expect(Kwh.fromDouble(42.05).format(), '42.1 kWh');
      expect(Kwh.zero.format(), '0.0 kWh');
    });
  });

  group('Naira', () {
    test('formats with thousands separators and no kobo', () {
      // A thin space follows the naira sign: its crossbars otherwise run
      // into the first digit and the amount reads as struck through.
      const n = Naira.naira;
      expect(Naira.fromNaira(2500000).format(), '${n}2,500,000');
      expect(Naira.fromNaira(1234).format(), '${n}1,234');
      expect(Naira.fromNaira(999).format(), '${n}999');
      expect(Naira.zero.format(), '${n}0');
    });

    test('the naira sign is followed by a narrow no-break space', () {
      // Thin space (U+2009) kerned correctly but allowed a line break, so a
      // wrapped amount in the dispute pack printed the sign at the end of
      // one line and the figure at the start of the next. U+202F kerns the
      // same and does not break.
      expect(Naira.naira, '₦\u202F');
      expect(Naira.naira.contains(' '), isFalse,
          reason: 'a normal space would look like a gap, not like kerning');
      expect(Naira.naira.contains('\u2009'), isFalse,
          reason: 'a breaking thin space orphans the sign from the amount');
    });

    test('formatTight closes the gap for renderers that break on it', () {
      // The PDF layer treats U+202F as ordinary whitespace and wraps on it,
      // so a dispute pack printed the sign at the end of one line and the
      // amount at the start of the next.
      expect(Naira.fromNaira(52204).formatTight(), '₦52,204');
      expect(Naira.fromNaira(52204).formatTight().contains('\u202F'), isFalse);
      expect(Naira.fromNaira(-1500).formatTight(), '-₦1,500');
    });

    test('handles negatives', () {
      expect(Naira.fromNaira(-1500).format(), '-${Naira.naira}1,500');
    });

    test('arithmetic is exact', () {
      final total = List.generate(3, (_) => Naira.fromNaira(0.1))
          .fold(Naira.zero, (a, b) => a + b);
      expect(total.kobo, 30);
    });
  });

  group('Rate', () {
    test('costs energy correctly', () {
      final rate = Rate.fromNaira(225);
      expect(rate.costOf(Kwh.fromDouble(10)).format(), '${Naira.naira}2,250');
    });

    test('inverts to energy for a given spend', () {
      final rate = Rate.fromNaira(225);
      final units = rate.energyFor(Naira.fromNaira(22500));
      expect(units.value, closeTo(100, 0.01));
    });

    test('a zero rate yields zero energy rather than dividing by zero', () {
      expect(const Rate.fromKobo(0).energyFor(Naira.fromNaira(1000)), Kwh.zero);
    });

    test('formats to two decimals', () {
      expect(Rate.fromNaira(225.5).format(), '${Naira.naira}225.50/kWh');
    });
  });
}
