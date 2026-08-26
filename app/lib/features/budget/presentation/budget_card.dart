import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/budget_engine.dart';
import '../application/budget_providers.dart';
import 'budget_sheet.dart';

/// The forecast, told as a decision.
///
/// Everything else in Grid is for the day something is wrong. This is the
/// line that makes the app worth opening on a day when nothing is.
class BudgetCard extends ConsumerWidget {
  const BudgetCard({super.key, required this.meterId});

  final String meterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final budget = ref.watch(budgetProvider(meterId)).value;
    final outlook = ref.watch(budgetOutlookProvider(meterId));

    if (budget == null) {
      return Material(
        color: c.surfaceRaised,
        borderRadius: Radii.mdAll,
        child: InkWell(
          borderRadius: Radii.mdAll,
          onTap: () => showBudgetSheet(context, meterId: meterId),
          child: Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              borderRadius: Radii.mdAll,
              border: Border.all(color: c.outline),
            ),
            child: Row(
              children: [
                Icon(Icons.savings_outlined, size: 20, color: c.textSecondary),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    'Set a budget and a pay day, and Grid will tell you '
                    'whether your units reach it.',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: c.textTertiary),
              ],
            ),
          ),
        ),
      );
    }

    final (accent, headline, detail) = switch (outlook) {
      null => (
          c.textSecondary,
          'Working it out',
          'Log a reading and Grid can place this cycle against your budget.',
        ),
      BudgetUnknown(:final reason) => (c.textSecondary, 'Not enough yet', reason),
      final BudgetOnTrack o => (
          c.supplyOn,
          '${o.headroom.format()} to spare',
          'Projected ${o.projected.format()} against a '
              '${o.budget.monthly.format()} budget, with '
              '${o.daysToPayDate(DateTime.now())} days to your pay day.',
        ),
      final BudgetShort o => (
          c.warning,
          '${o.shortfall.format()} short',
          o.runsOutOn == null
              ? 'This cycle is heading for ${o.projected.format()} against a '
                  '${o.budget.monthly.format()} budget.'
              : 'Your units run out on '
                  '${friendlyDate(o.runsOutOn!, now: DateTime.now())}, '
                  '${o.gapDays()} days before you are paid. That is what it '
                  'costs to bridge the gap.',
        ),
    };

    return Material(
      color: c.surfaceRaised,
      borderRadius: Radii.mdAll,
      child: InkWell(
        borderRadius: Radii.mdAll,
        onTap: () =>
            showBudgetSheet(context, meterId: meterId, existing: budget),
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            borderRadius: Radii.mdAll,
            border: Border.all(
              color: outlook is BudgetShort
                  ? c.warning.withValues(alpha: 0.35)
                  : c.outline,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: Text(
                      headline,
                      style: t.title.copyWith(color: c.textPrimary),
                    ),
                  ),
                  Icon(Icons.tune_rounded, size: 16, color: c.textTertiary),
                ],
              ),
              const SizedBox(height: Space.xs),
              Text(detail, style: t.caption.copyWith(color: c.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
