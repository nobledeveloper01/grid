import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/generator_engine.dart';
import '../../../domain/services/load_model_engine.dart';
import '../../../domain/services/solar_sizing_engine.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';
import '../application/economics_providers.dart';
import 'generator_sheets.dart';

/// What power actually costs this household, across both sources.
///
/// Phase 8. Nobody in this market consumes only grid electricity, so every
/// figure elsewhere in Grid describes half the bill. This screen is the other
/// half, and the comparison between them.
class EconomicsScreen extends ConsumerWidget {
  const EconomicsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    if (meter == null) {
      return const GridScaffold(
        title: 'Running costs',
        body: SizedBox.shrink(),
      );
    }

    final c = context.colors;
    final t = context.type;
    final cost = ref.watch(generatorCostProvider(meter.id));
    final blend = ref.watch(blendedCostProvider(meter.id));
    final sizing = ref.watch(solarSizingProvider(meter.id));
    final coach = ref.watch(applianceCoachProvider(meter.id));
    final running = ref.watch(ongoingRunProvider(meter.id));
    final sets = ref.watch(generatorsProvider(meter.id)).value ?? const [];
    final now = ref.watch(clockProvider)();

    return GridScaffold(
      title: 'Running costs',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          if (sets.isEmpty)
            InfoNote(
              icon: Icons.bolt_outlined,
              message: 'Tell Grid what you run when the power is out, and it '
                  'can work out what a generated unit costs you against a '
                  'grid one.',
              actions: [
                FilledButton.tonal(
                  onPressed: () =>
                      showGeneratorSheet(context, meterId: meter.id),
                  child: const Text('Add a generator'),
                ),
              ],
            )
          else ...[
            _GeneratorCost(cost: cost, blend: blend),
            const SizedBox(height: Space.md),
            _FuelRow(meterId: meter.id),
          ],

          if (running != null) ...[
            const SizedBox(height: Space.md),
            _RunningNow(hours: running.hours(now)),
          ],

          const SizedBox(height: Space.xl),
          Text('Would solar be cheaper?',
              style: t.title.copyWith(color: c.textPrimary)),
          const SizedBox(height: Space.md),
          _Sizing(sizing: sizing),

          if (coach.isNotEmpty) ...[
            const SizedBox(height: Space.xl),
            Text('What is costing the most',
                style: t.title.copyWith(color: c.textPrimary)),
            const SizedBox(height: Space.sm),
            Text(
              'Modelled from your inventory and pegged to what the meter '
              'actually recorded, so the savings are the ones you could '
              'really make.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: Space.md),
            for (final item in coach.take(6))
              _CoachRow(cost: item, meterId: meter.id),
          ],

          const SizedBox(height: Space.xxxl),
        ],
      ),
      bottom: sets.isEmpty
          ? null
          : FilledButton.icon(
              onPressed: () => running == null
                  ? ref
                      .read(generatorControllerProvider.notifier)
                      .start(meter.id)
                  : ref
                      .read(generatorControllerProvider.notifier)
                      .stop(meter.id),
              icon: Icon(running == null
                  ? Icons.play_arrow_rounded
                  : Icons.stop_rounded),
              label: Text(running == null
                  ? 'Generator started'
                  : 'Generator stopped'),
            ),
    );
  }
}

class _GeneratorCost extends StatelessWidget {
  const _GeneratorCost({required this.cost, required this.blend});

  final GeneratorCost cost;
  final BlendedCost? blend;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    if (cost is GeneratorCostUnknown) {
      final u = cost as GeneratorCostUnknown;
      return InfoNote(
        icon: Icons.timer_outlined,
        message: switch (u.reason) {
          GeneratorGap.noRuns =>
            'Log ${u.needed} more ${u.needed == 1 ? 'run' : 'runs'} and Grid '
                'can price a generated unit.',
          GeneratorGap.noFuel =>
            'Grid has your running hours but no fuel. Log a purchase and the '
                'rate follows.',
          GeneratorGap.noOverlap =>
            'The fuel and the running do not line up over the same period '
                'yet, so dividing one by the other would be a guess.',
        },
      );
    }

    final k = cost as GeneratorCostKnown;
    final b = blend;

    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: Radii.lgAll,
        border: Border.all(color: c.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'GENERATED POWER · LAST $economicsWindowDays DAYS',
            style: t.label.copyWith(color: c.textSecondary, letterSpacing: 0.8),
          ),
          const SizedBox(height: Space.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              k.rate.format(),
              maxLines: 1,
              style: t.display.copyWith(color: c.warning),
            ),
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${k.litres.toStringAsFixed(0)} litres and '
            '${k.spend.format()} over ${formatHours(k.hours)} of running — '
            'about ${k.energy.format()} generated.',
            style: t.body.copyWith(color: c.textSecondary),
          ),
          if (b != null && b.multiple != null) ...[
            const SizedBox(height: Space.lg),
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: c.warningSoft,
                borderRadius: Radii.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${b.multiple!.toStringAsFixed(1)}× the grid rate',
                    style: t.headline.copyWith(color: c.warning),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Grid power costs you ${b.gridRate.format()}. Blended '
                    'across both, you are paying '
                    '${b.blendedRate.format()} — and '
                    '${formatPercent(b.generatorShare)} of your energy came '
                    'off the generator.',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: Space.md),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Space.sm, vertical: 2),
                decoration: BoxDecoration(
                  color: c.estimateSoft,
                  borderRadius: Radii.smAll,
                ),
                child: Text(
                  'MODELLED',
                  style: t.caption.copyWith(
                      color: c.estimate, fontSize: 10, letterSpacing: 0.6),
                ),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  k.isRough
                      ? 'A generator has no meter, so its output is modelled '
                          'from the plate rating. ${k.runCount} runs is thin — '
                          'the rate will settle as you log more.'
                      : 'A generator has no meter, so its output is modelled '
                          'from the plate rating rather than measured.',
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunningNow extends StatelessWidget {
  const _RunningNow({required this.hours});

  final double hours;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: Radii.mdAll,
      ),
      child: Row(
        children: [
          Icon(Icons.local_fire_department_rounded, size: 20, color: c.brand),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              'Running for ${formatHours(hours)}.',
              style: t.body.copyWith(color: c.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _FuelRow extends ConsumerWidget {
  const _FuelRow({required this.meterId});

  final String meterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final fuel = ref.watch(fuelProvider(meterId)).value ?? const [];
    final latest = fuel.firstOrNull;

    return Material(
      color: c.surfaceRaised,
      borderRadius: Radii.mdAll,
      child: InkWell(
        borderRadius: Radii.mdAll,
        onTap: () => showFuelSheet(context, meterId: meterId),
        child: Container(
          padding: const EdgeInsets.all(Space.lg),
          constraints: const BoxConstraints(minHeight: Targets.min),
          decoration: BoxDecoration(
            borderRadius: Radii.mdAll,
            border: Border.all(color: c.outline),
          ),
          child: Row(
            children: [
              Icon(Icons.local_gas_station_outlined,
                  size: 20, color: c.textSecondary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  latest == null
                      ? 'Log a fuel purchase'
                      : 'Last fuel: ${latest.amount.format()} for '
                          '${latest.litres.toStringAsFixed(0)} litres, '
                          '${latest.perLitre.format()} a litre',
                  style: t.body.copyWith(color: c.textPrimary),
                ),
              ),
              Icon(Icons.add_rounded, size: 18, color: c.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

class _Sizing extends StatelessWidget {
  const _Sizing({required this.sizing});

  final SolarSizing sizing;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    if (sizing is SizingUnavailable) {
      return InfoNote(
        icon: Icons.solar_power_outlined,
        message: (sizing as SizingUnavailable).detail,
      );
    }

    final s = sizing as Sized;
    final p = s.payback;

    return Container(
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: Radii.lgAll,
        border: Border.all(color: c.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _Spec(label: 'Panels', value: '${s.panelKw} kW'),
              ),
              Expanded(
                child: _Spec(label: 'Battery', value: '${s.batteryKwh} kWh'),
              ),
              Expanded(
                child: _Spec(label: 'Inverter', value: '${s.inverterKw} kW'),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(
            'Sized against the ${s.dailyKwh.format()} a day you actually use, '
            'with the battery set to carry your longest measured outage — '
            '${formatHours(s.longestOutageHours)}, not the average.',
            style: t.body.copyWith(color: c.textSecondary),
          ),
          if (p != null) ...[
            const SizedBox(height: Space.lg),
            Container(
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: Radii.mdAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${p.systemCostLow.format()} – ${p.systemCostHigh.format()}',
                    style: t.title.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Against the ${p.monthlyGeneratorSpend.format()} of fuel '
                    'you logged this period, that is roughly '
                    '${p.monthsLow}–${p.monthsHigh} months to pay for itself.',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: Space.md),
            Text(
              'Log what you spend on fuel and Grid can work out how long a '
              'system would take to pay for itself. It will not invent a '
              'figure to do it.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
          ],
          const SizedBox(height: Space.lg),
          Text(
            'WHAT THIS DOES NOT KNOW',
            style: t.caption.copyWith(
                color: c.estimate, letterSpacing: 0.6, fontSize: 10),
          ),
          const SizedBox(height: Space.xs),
          for (final u in s.unknowns)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text('· $u',
                  style: t.caption.copyWith(color: c.textTertiary)),
            ),
        ],
      ),
    );
  }
}

class _Spec extends StatelessWidget {
  const _Spec({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: t.title.copyWith(color: c.brand)),
        Text(label, style: t.caption.copyWith(color: c.textSecondary)),
      ],
    );
  }
}

class _CoachRow extends ConsumerWidget {
  const _CoachRow({required this.cost, required this.meterId});

  final ApplianceCost cost;
  final String meterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final a = cost.appliance;

    // The reduction offered has to be proportional to what the thing actually
    // runs. "One hour a day less" for a water heater that runs forty-eight
    // minutes is both nonsense and, because the saving clamps at the whole
    // cost, arithmetic that looks broken: it offered to save 100% of the bill.
    final (giveUp, phrase) = switch (a.hoursPerDay) {
      >= 4 => (1.0, 'One hour a day less'),
      >= 1.5 => (0.5, 'Half an hour a day less'),
      _ => (a.hoursPerDay / 2, 'Running it half as often'),
    };
    final saving = cost.savingFromRunningLess(giveUp);

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.quantity > 1 ? '${a.name} ×${a.quantity}' : a.name,
                  style: t.body.copyWith(color: c.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  saving.isZero
                      ? '${a.ratedWatts} W · ${a.hoursPerDay <= 0 ? 'never runs' : 'runs briefly'}'
                      : '$phrase saves about ${saving.format()} a month',
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          Text(
            cost.monthlyCost.format(),
            style: t.figure.copyWith(color: c.estimate),
          ),
        ],
      ),
    );
  }
}
