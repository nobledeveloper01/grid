import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../domain/services/compliance_engine.dart';

/// Seven bars: one per day, filled in proportion to hours of supply.
///
/// The bar height encodes the hours, so the strip is readable in greyscale
/// and to a screen reader — colour is the second signal, never the only one.
/// Days we barely observed render flat in `supplyUnknown`, which is
/// deliberately low-salience because missing data is normal here.
class SupplyStrip extends StatelessWidget {
  const SupplyStrip({super.key, required this.days, this.maxHeight = 72});

  final List<DailySupply> days;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    if (days.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: c.surfaceDim,
          borderRadius: Radii.mdAll,
          border: Border.all(color: c.outline),
        ),
        child: Row(
          children: [
            Icon(Icons.power_off_rounded, size: 20, color: c.textTertiary),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                "No power log yet — tell Grid when the power goes off and "
                "it'll start building your record.",
                style: t.caption.copyWith(color: c.textSecondary),
              ),
            ),
          ],
        ),
      );
    }

    final best = days
        .where((d) => d.isUsable)
        .fold<double>(0, (a, d) => d.hours > a ? d.hours : a);

    return SizedBox(
      height: maxHeight + 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++) ...[
            Expanded(
              child: _Bar(
                day: days[i],
                maxHeight: maxHeight,
                isBest: days[i].isUsable && best > 0 && days[i].hours == best,
                index: i,
              ),
            ),
            if (i != days.length - 1) const SizedBox(width: Space.sm),
          ],
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.day,
    required this.maxHeight,
    required this.isBest,
    required this.index,
  });

  final DailySupply day;
  final double maxHeight;
  final bool isBest;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    // Height carries the data; a floor keeps an empty day tappable and
    // visible rather than collapsing to nothing.
    const floor = 10.0;
    final fill = day.isUsable
        ? floor + (day.hours / 24).clamp(0.0, 1.0) * (maxHeight - floor)
        : floor;

    final gradient = day.isUsable
        ? LinearGradient(
            colors: [c.supplyOn, c.supplyOn.withValues(alpha: 0.55)],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          )
        : null;

    return Semantics(
      label: day.isUsable
          ? '${weekdayName(day.date)}: ${formatHours(day.hours)} of power'
          : '${weekdayName(day.date)}: not enough data',
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // The track, so a short bar still reads as "short" rather than as
          // "missing".
          Container(
            height: maxHeight,
            alignment: Alignment.bottomCenter,
            decoration: BoxDecoration(
              color: c.track,
              borderRadius: Radii.smAll,
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: fill),
              duration: Motion.chart + Motion.stagger * index,
              curve: Curves.easeOutCubic,
              builder: (context, height, _) => Container(
                height: height,
                decoration: BoxDecoration(
                  gradient: gradient,
                  color: gradient == null ? c.supplyUnknown : null,
                  borderRadius: Radii.smAll,
                  boxShadow: isBest ? Shadows.glow(c.supplyOn) : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            weekdayName(day.date).substring(0, 1),
            style: t.caption.copyWith(
              color: day.isUsable ? c.textSecondary : c.textTertiary,
              fontWeight: isBest ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
