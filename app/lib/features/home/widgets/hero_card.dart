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
/// For a prepaid user this is the wedge: the days-to-depletion figure that
/// makes the app worth opening every week.
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

class _HeroShell extends StatelessWidget {
  const _HeroShell({
    required this.label,
    required this.headline,
    this.detail,
    this.tone,
  });

  final String label;
  final Widget headline;
  final String? detail;
  final Color? tone;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: Radii.lgAll,
        border: Border.all(color: tone ?? c.outline, width: tone != null ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.label.copyWith(color: c.textSecondary)),
          const SizedBox(height: Space.md),
          headline,
          if (detail != null) ...[
            const SizedBox(height: Space.sm),
            Text(detail!, style: t.body.copyWith(color: c.textSecondary)),
          ],
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
      return _HeroShell(
        label: 'Units remaining',
        headline: Text('Not enough data yet', style: t.title),
        detail: switch (forecast.reason) {
          ForecastUnavailableReason.notEnoughReadings =>
            'Log ${forecast.readingsNeeded} more reading'
                '${forecast.readingsNeeded == 1 ? '' : 's'} and Grid can tell '
                'you when your units finish.',
          ForecastUnavailableReason.noConsumptionYet =>
            "Your readings haven't changed yet. Log another one in a day or "
                'two.',
          _ => 'Log a reading to get started.',
        },
      );
    }

    final f = forecast as BalanceKnown;
    final days = f.daysRemaining;
    final tone = f.isUrgent
        ? c.danger
        : (f.needsWarning ? c.warning : null);

    return _HeroShell(
      label: 'Your units finish',
      tone: tone,
      headline: Text(
        friendlyDate(f.depletesOn, now: now),
        style: t.display.copyWith(color: tone ?? c.textPrimary),
      ),
      detail: f.isRough
          ? 'Roughly — about ${days.toStringAsFixed(days < 2 ? 1 : 0)} days '
              'left at ${f.dailyMean.toStringAsFixed(1)} kWh a day. Log more '
              'readings and this gets sharper.'
          : '${f.balance.format()} left, at about '
              '${f.dailyMean.toStringAsFixed(1)} kWh a day.',
    );
  }
}

class _PostpaidHero extends ConsumerWidget {
  const _PostpaidHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider)!;
    final projection = ref.watch(costProjectionProvider(meter.id));
    final t = context.type;

    if (projection is CostUnavailable) {
      return _HeroShell(
        label: 'This month',
        headline: Text('Not enough data yet', style: t.title),
        detail: 'Log ${projection.readingsNeeded} more reading'
            '${projection.readingsNeeded == 1 ? '' : 's'} and Grid can '
            'project your bill.',
      );
    }
    if (projection == null) {
      return _HeroShell(
        label: 'This month',
        headline: Text('Set your rate', style: t.title),
        detail: 'Grid needs your tariff band to work out cost.',
      );
    }

    final p = projection as CostProjected;
    return _HeroShell(
      label: 'Projected bill this month',
      headline: Text(p.projectedCost.format(), style: t.display),
      detail: p.isRough
          ? 'Somewhere between ${p.lowCost.format()} and '
              '${p.highCost.format()} — only ${p.daysOfData} days of '
              'readings so far.'
          : '${p.projectedKwh.format()} at ${p.rate.format()}. '
              'Range ${p.lowCost.format()}–${p.highCost.format()}.',
    );
  }
}

class _UnmeteredHero extends ConsumerWidget {
  const _UnmeteredHero();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = context.type;
    return _HeroShell(
      label: 'Estimated billing',
      headline: Text('Build your case', style: t.headline),
      detail: 'You have no meter, so Grid works out what you actually use '
          'from the things you run. That is what a dispute needs.',
    );
  }
}
