import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/forecast_engine.dart';
import '../../../domain/value_objects/enums.dart';
import '../../meter/application/meter_providers.dart';

/// The home screen's hero. One number, chosen by meter type.
///
/// This is the only gradient surface in the app, and that scarcity is what
/// makes it work: exactly one thing per screen is the thing you came for.
class HeroCard extends ConsumerWidget {
  const HeroCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    if (meter == null) return const SizedBox.shrink();

    return switch (meter.type) {
      MeterType.prepaidKeypad => const _PrepaidHero(),
      MeterType.unmeteredEstimated => const _UnmeteredHero(),
      _ => const _PostpaidHero(),
    };
  }
}

/// The lit variant: a gradient card carrying a figure worth celebrating.
class _LitHero extends StatelessWidget {
  const _LitHero({
    required this.label,
    required this.headline,
    required this.detail,
    this.icon = Icons.bolt_rounded,
    this.footer,
  });

  final String label;
  final String headline;
  final String detail;
  final IconData icon;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: c.heroGradient,
        borderRadius: Radii.xlAll,
        boxShadow: Shadows.glow(c.gradientEnd),
      ),
      child: Stack(
        children: [
          // A soft light source in the corner, so the gradient reads as lit
          // rather than as a flat fill.
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: c.onBrand.withValues(alpha: 0.75)),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: Text(
                        label.toUpperCase(),
                        style: t.label.copyWith(
                          color: c.onBrand.withValues(alpha: 0.75),
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.lg),
                // Shrunk to fit rather than wrapped. At the larger
                // accessibility sizes this figure broke mid-thousands —
                // "₦65,7 / 80" — and a money amount split across two
                // lines is less readable than the same amount a size down,
                // not more. It still scales with Dynamic Type; it just stops
                // growing once it would have to break.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    headline,
                    maxLines: 1,
                    softWrap: false,
                    style: t.display.copyWith(color: c.onBrand, height: 1.05),
                  ),
                ),
                const SizedBox(height: Space.md),
                Text(
                  detail,
                  style: t.body.copyWith(
                    color: c.onBrand.withValues(alpha: 0.85),
                  ),
                ),
                if (footer != null) ...[
                  const SizedBox(height: Space.lg),
                  footer!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The quiet variant: used when there is nothing to celebrate yet, so the
/// gradient is not spent on an empty state.
class _QuietHero extends StatelessWidget {
  const _QuietHero({
    required this.label,
    required this.headline,
    required this.detail,
    this.icon = Icons.insights_rounded,
  });

  final String label;
  final String headline;
  final String detail;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: Radii.xlAll,
        border: Border.all(color: c.brand.withValues(alpha: 0.28), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: c.brandDeep),
              const SizedBox(width: Space.sm),
              Text(
                label.toUpperCase(),
                style: t.label.copyWith(
                  color: c.brandDeep,
                  letterSpacing: 1.1,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(headline, style: t.title),
          const SizedBox(height: Space.sm),
          Text(detail, style: t.body.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}

class _PrepaidHero extends ConsumerWidget {
  const _PrepaidHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider)!;
    final forecast = ref.watch(balanceForecastProvider(meter.id));
    final now = ref.watch(clockProvider)();
    final c = context.colors;
    final t = context.type;

    if (forecast is BalanceUnavailable) {
      return _QuietHero(
        label: 'Units remaining',
        icon: Icons.hourglass_empty_rounded,
        headline: 'Not enough data yet',
        detail: switch (forecast.reason) {
          ForecastUnavailableReason.notEnoughReadings =>
            'Log ${forecast.readingsNeeded} more reading'
                '${forecast.readingsNeeded == 1 ? '' : 's'} and Grid can tell '
                'you when your units finish.',
          ForecastUnavailableReason.noConsumptionYet =>
            "Your readings haven't changed yet. Log another one in a day or two.",
          _ => 'Log a reading to get started.',
        },
      );
    }

    final f = forecast as BalanceKnown;

    return _LitHero(
      label: 'Your units finish',
      icon: Icons.bolt_rounded,
      headline: friendlyDate(f.depletesOn, now: now),
      detail: f.isRough
          ? 'Roughly — about ${f.daysRemaining.toStringAsFixed(f.daysRemaining < 2 ? 1 : 0)} '
              'days left. Log more readings and this gets sharper.'
          : '${f.balance.format()} left, at about '
              '${f.dailyMean.toStringAsFixed(1)} kWh a day.',
      footer: Row(
        children: [
          _HeroChip(
            icon: Icons.battery_charging_full_rounded,
            label: f.balance.format(),
          ),
          const SizedBox(width: Space.sm),
          _HeroChip(
            icon: Icons.trending_down_rounded,
            label: '${f.dailyMean.toStringAsFixed(1)} kWh/day',
          ),
          if (f.needsWarning) ...[
            const SizedBox(width: Space.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Space.md,
                vertical: Space.sm,
              ),
              decoration: BoxDecoration(
                color: c.onBrand,
                borderRadius: Radii.smAll,
              ),
              child: Text(
                f.isUrgent ? 'Buy now' : 'Buy soon',
                style: t.caption.copyWith(
                  color: c.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PostpaidHero extends ConsumerWidget {
  const _PostpaidHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider)!;
    final projection = ref.watch(costProjectionProvider(meter.id));

    if (projection is CostUnavailable) {
      return _QuietHero(
        label: 'This month',
        icon: Icons.hourglass_empty_rounded,
        headline: 'Not enough data yet',
        detail: 'Log ${projection.readingsNeeded} more reading'
            '${projection.readingsNeeded == 1 ? '' : 's'} and Grid can '
            'project your bill before it arrives.',
      );
    }
    if (projection == null) {
      return const _QuietHero(
        label: 'This month',
        icon: Icons.tune_rounded,
        headline: 'Set your rate',
        detail: 'Grid needs your tariff band to work out what power costs you.',
      );
    }

    final p = projection as CostProjected;
    // The headline is the *whole cycle*, and the label says so. It read
    // "Bill so far this month" over a figure that covered only the days
    // still to come — neither what had been spent nor what the bill would
    // be. What has actually been spent is now stated underneath, where it
    // can be checked against the meter.
    return _LitHero(
      label: 'Bill this month',
      icon: Icons.receipt_long_rounded,
      headline: p.projectedCost.format(),
      detail: p.isRough
          ? 'Somewhere between ${p.lowCost.format()} and '
              '${p.highCost.format()} — only ${p.daysOfData} days of '
              'readings so far.'
          : '${p.costSoFar.format()} so far, from '
              '${p.consumedSoFar.format()} at ${p.rate.format()}.',
      footer: Row(
        children: [
          _HeroChip(
            icon: Icons.speed_rounded,
            label: '${p.dailyMean.toStringAsFixed(1)} kWh/day',
          ),
          const SizedBox(width: Space.sm),
          _HeroChip(
            icon: Icons.swap_vert_rounded,
            label: '${p.lowCost.format()}–${p.highCost.format()}',
          ),
        ],
      ),
    );
  }
}

class _UnmeteredHero extends StatelessWidget {
  const _UnmeteredHero();

  @override
  Widget build(BuildContext context) {
    return const _LitHero(
      label: 'Estimated billing',
      icon: Icons.gavel_rounded,
      headline: 'Build your case',
      detail: 'You have no meter, so Grid works out what you actually use from '
          'the things you run. That is what a dispute needs.',
    );
  }
}

/// A small translucent pill on the gradient. Carries a supporting figure
/// without competing with the headline.
class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.md,
          vertical: Space.sm,
        ),
        decoration: BoxDecoration(
          color: c.onBrand.withValues(alpha: 0.14),
          borderRadius: Radii.smAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: c.onBrand.withValues(alpha: 0.8)),
            const SizedBox(width: Space.xs),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: t.caption.copyWith(
                  color: c.onBrand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
