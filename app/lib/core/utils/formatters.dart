/// Presentation formatting.
///
/// Dates are spelled out with the weekday, because "finishes Thursday 14th"
/// lands and "14/08" does not.
library;

const _weekdays = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];
String monthName(DateTime d) => _months[d.month - 1];

String ordinal(int day) {
  if (day >= 11 && day <= 13) return '${day}th';
  return switch (day % 10) {
    1 => '${day}st',
    2 => '${day}nd',
    3 => '${day}rd',
    _ => '${day}th',
  };
}

/// "Thursday 14th" for dates inside the next week, "Thursday 14 September"
/// beyond it. Relative words are used where they are genuinely clearer.
String friendlyDate(DateTime date, {required DateTime now}) {
  final d = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final delta = d.difference(today).inDays;

  if (delta == 0) return 'today';
  if (delta == 1) return 'tomorrow';
  if (delta == -1) return 'yesterday';
  if (delta > 1 && delta < 7) {
    return '${weekdayName(d)} ${ordinal(d.day)}';
  }
  return '${weekdayName(d)} ${d.day} ${monthName(d)}';
}

/// "2 days ago", "just now". Used for reading recency and coverage notes.
String relativeTime(DateTime then, {required DateTime now}) {
  final delta = now.difference(then);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inMinutes < 60) return '${delta.inMinutes} min ago';
  if (delta.inHours < 24) {
    return '${delta.inHours} hour${delta.inHours == 1 ? '' : 's'} ago';
  }
  if (delta.inDays == 1) return 'yesterday';
  if (delta.inDays < 30) return '${delta.inDays} days ago';
  final months = delta.inDays ~/ 30;
  return '$months month${months == 1 ? '' : 's'} ago';
}

/// A date and how long ago it was, without saying the same word twice.
///
/// `friendlyDate` and `relativeTime` both collapse to "yesterday" one day
/// out, and the reading history was rendering "yesterday · yesterday".
String dateAndAge(DateTime then, {required DateTime now}) {
  final date = friendlyDate(then, now: now);
  final age = relativeTime(then, now: now);
  return date.toLowerCase() == age.toLowerCase() ? date : '$date · $age';
}

/// Hours as "11.2 hours" or "20 hours" — no spurious decimal on a round
/// number.
String formatHours(double hours) {
  final rounded = (hours * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) {
    return '${rounded.round()} hours';
  }
  return '${rounded.toStringAsFixed(1)} hours';
}

String formatPercent(double ratio) => '${(ratio * 100).round()}%';
