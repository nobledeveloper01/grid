import '../value_objects/units.dart';
import 'forecast_engine.dart';

/// A monthly spending limit, and the day money next arrives.
///
/// Both are *state*: they change, last write wins, and there is nothing
/// evidential about them.
class Budget {
  const Budget({required this.monthly, required this.payDayOfMonth});

  final Naira monthly;

  /// 1–31. Clamped to the length of the month when it is applied, so a pay
  /// day of the 31st still lands in February.
  final int payDayOfMonth;

  /// The next occurrence of the pay day, at or after [from].
  DateTime nextPayDate(DateTime from) {
    DateTime inMonth(int year, int month) {
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, payDayOfMonth.clamp(1, lastDay));
    }

    final thisMonth = inMonth(from.year, from.month);
    if (!thisMonth.isBefore(DateTime(from.year, from.month, from.day))) {
      return thisMonth;
    }
    return inMonth(from.year, from.month + 1);
  }
}

/// Where a household stands against its own budget.
sealed class BudgetOutlook {
  const BudgetOutlook({required this.budget, required this.payDate});

  final Budget budget;
  final DateTime payDate;

  int daysToPayDate(DateTime now) =>
      payDate.difference(DateTime(now.year, now.month, now.day)).inDays;
}

/// Nothing to say yet — usually too little history for a forecast.
class BudgetUnknown extends BudgetOutlook {
  const BudgetUnknown({
    required super.budget,
    required super.payDate,
    required this.reason,
  });

  final String reason;
}

class BudgetOnTrack extends BudgetOutlook {
  const BudgetOnTrack({
    required super.budget,
    required super.payDate,
    required this.headroom,
    required this.projected,
  });

  /// What is left of the budget at the projected rate.
  final Naira headroom;

  /// What the cycle is projected to cost.
  final Naira projected;
}

class BudgetShort extends BudgetOutlook {
  const BudgetShort({
    required super.budget,
    required super.payDate,
    required this.shortfall,
    required this.projected,
    required this.runsOutOn,
  });

  final Naira shortfall;
  final Naira projected;

  /// When the money runs out, if that can be said. Null on a postpaid
  /// projection, where there is no balance to deplete — only a bill that
  /// will be larger than the budget.
  final DateTime? runsOutOn;

  /// Days between the money running out and the money arriving. The number
  /// the whole feature exists to produce.
  int? gapDays() {
    final out = runsOutOn;
    if (out == null) return null;
    final days = payDate.difference(out).inDays;
    return days < 0 ? 0 : days;
  }
}

/// Reframes a forecast against the date money next arrives.
///
/// The depletion forecast answers the wrong question by one step. A date is
/// only actionable against another date, and for most households in this
/// market that other date is salary day. "Your units finish on the 24th" is
/// information; "your units finish four days before you are paid" is a
/// decision.
class BudgetEngine {
  const BudgetEngine();

  /// Prepaid: units deplete on a date, and what matters is whether that date
  /// falls before the money arrives.
  BudgetOutlook fromBalance({
    required Budget budget,
    required BalanceForecast forecast,
    required Rate rate,
    required Naira spentThisCycle,
    required DateTime now,
  }) {
    final payDate = budget.nextPayDate(now);

    switch (forecast) {
      case BalanceUnavailable():
        return BudgetUnknown(
          budget: budget,
          payDate: payDate,
          reason: 'Grid needs a couple more readings before it can say '
              'whether your units reach your next pay day.',
        );
      case BalanceKnown(:final depletesOn, :final dailyMean):
        // What it would cost to buy through to the pay date at the current
        // rate of use.
        final daysToPay = payDate.difference(now).inMinutes / (60 * 24);
        final needed = rate.costOf(Kwh.fromDouble(dailyMean * daysToPay));
        final projected = spentThisCycle + needed;

        if (!depletesOn.isBefore(payDate)) {
          return BudgetOnTrack(
            budget: budget,
            payDate: payDate,
            headroom: budget.monthly - projected,
            projected: projected,
          );
        }

        // The units run out first. What is short is what it costs to bridge
        // the gap, not the whole projected spend.
        final gapDays =
            payDate.difference(depletesOn).inMinutes / (60 * 24);
        final bridge = rate.costOf(Kwh.fromDouble(dailyMean * gapDays));
        return BudgetShort(
          budget: budget,
          payDate: payDate,
          shortfall: bridge,
          projected: projected,
          runsOutOn: depletesOn,
        );
    }
  }

  /// Postpaid: there is no balance, only a bill that will be a certain size.
  BudgetOutlook fromProjection({
    required Budget budget,
    required CostProjection projection,
    required DateTime now,
  }) {
    final payDate = budget.nextPayDate(now);

    switch (projection) {
      case CostUnavailable():
        return BudgetUnknown(
          budget: budget,
          payDate: payDate,
          reason: 'Grid needs a couple more readings before it can project '
              'this cycle against your budget.',
        );
      case CostProjected(:final projectedCost):
        if (projectedCost > budget.monthly) {
          return BudgetShort(
            budget: budget,
            payDate: payDate,
            shortfall: projectedCost - budget.monthly,
            projected: projectedCost,
            runsOutOn: null,
          );
        }
        return BudgetOnTrack(
          budget: budget,
          payDate: payDate,
          headroom: budget.monthly - projectedCost,
          projected: projectedCost,
        );
    }
  }
}
