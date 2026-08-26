import 'package:flutter_test/flutter_test.dart';
import 'package:grid/core/utils/formatters.dart';

void main() {
  final now = DateTime(2026, 8, 26, 12);

  group('dateAndAge', () {
    test('does not say the same word twice', () {
      // Both halves collapse to "yesterday" one day out, and the reading
      // history was rendering "yesterday · yesterday".
      final yesterday = DateTime(2026, 8, 25, 12);
      expect(dateAndAge(yesterday, now: now), 'yesterday');
    });

    test('keeps both halves when they say different things', () {
      final lastWeek = DateTime(2026, 8, 20, 7, 40);
      final result = dateAndAge(lastWeek, now: now);
      expect(result, contains('·'));
      expect(result, contains('August'));
      expect(result, contains('ago'));
    });

    test('handles today, where the age is the more useful half', () {
      final earlier = DateTime(2026, 8, 26, 7);
      expect(dateAndAge(earlier, now: now), 'today · 5 hours ago');
    });
  });

  group('formatHours', () {
    test('drops a spurious decimal on a round number', () {
      expect(formatHours(20), '20 hours');
      expect(formatHours(11.24), '11.2 hours');
    });
  });

  group('formatPercent', () {
    test('rounds to whole percent', () {
      expect(formatPercent(0.876), '88%');
      expect(formatPercent(1), '100%');
      expect(formatPercent(0), '0%');
    });
  });
}
