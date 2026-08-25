import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../domain/services/compliance_engine.dart';

/// Seven bars: one per day, filled in proportion to hours of supply.
///
/// Days we barely observed render in `supplyUnknown`, which is deliberately
/// flat and low-salience — missing data is normal here and must not read as
/// an error.
class SupplyStrip extends StatelessWidget {
  const SupplyStrip({super.key, required this.days});

  final List<DailySupply> days;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    if (days.isEmpty) {
      return Text(
        "No power log yet — tell Grid when the power goes off and it'll "
        'start building your record.',
        style: t.caption.copyWith(color: c.textSecondary),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 56,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final day in days) ...[
                Expanded(
                  child: Semantics(
                    label: day.isUsable
                        ? '${weekdayName(day.date)}: '
                            '${formatHours(day.hours)} of power'
                        : '${weekdayName(day.date)}: not enough data',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: day.isUsable
                              ? (8 + (day.hours / 24) * 32)
                              : 8,
                          decoration: BoxDecoration(
                            color: day.isUsable ? c.supplyOn : c.supplyUnknown,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(3),
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        Text(
                          weekdayName(day.date).substring(0, 1),
                          style: t.caption.copyWith(color: c.textTertiary),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: Space.xs),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
