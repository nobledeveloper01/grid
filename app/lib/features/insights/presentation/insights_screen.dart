import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/charts/trend_chart.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../home/widgets/section_header.dart';
import '../../meter/application/meter_providers.dart';
import '../application/insights_providers.dart';
import '../widgets/attribution_list.dart';
import 'package:go_router/go_router.dart';

/// Trend, cost and where the units go.
///
/// Every figure on this screen is one of two kinds, and the screen never
/// lets them look alike: measured, from the meter, drawn solid; or modelled,
/// from the appliance inventory, drawn in `estimate` and labelled.
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  int _days = 30;
  bool _showCost = false;

  @override
  Widget build(BuildContext context) {
    final meter = ref.watch(selectedMeterProvider);

    if (meter == null) {
      return const GridScaffold(title: 'Insights', body: SizedBox.shrink());
    }

    final args = (meterId: meter.id, days: _days);
    final series = ref.watch(consumptionSeriesProvider(args));
    final points = _showCost
        ? ref.watch(costTrendProvider(args))
        : ref.watch(consumptionTrendProvider(args));
    final rate = ref.watch(effectiveRateProvider(meter.id));
    final model = ref.watch(loadModelProvider(meter.id));
    final hasSupply = ref.watch(loadModelHasSupplyProvider(meter.id));

    return GridScaffold(
      title: 'Insights',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          _WindowPicker(
            days: _days,
            onChanged: (d) => setState(() => _days = d),
          ),
          const SizedBox(height: Space.lg),

          _Toggle(
            showCost: _showCost,
            canShowCost: rate != null,
            onChanged: (v) => setState(() => _showCost = v),
          ),
          const SizedBox(height: Space.lg),

          TrendChart(
            points: points,
            valueLabel: 'a day',
            formatValue: (v) => _showCost
                ? Naira.fromNaira(v).format()
                : Kwh.fromDouble(v).format(),
          ),
          const SizedBox(height: Space.xl),

          if (series != null && series.hasData) ...[
            Row(
              children: [
                Expanded(
                  child: _Figure(
                    label: 'Used in $_days days',
                    value: series.total.format(),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _Figure(
                    label: 'Daily average',
                    value: Kwh.fromDouble(series.dailyMean).format(),
                  ),
                ),
              ],
            ),
            if (series.excludedReadingCount > 0) ...[
              const SizedBox(height: Space.md),
              InfoNote(
                message: '${series.excludedReadingCount} '
                    '${series.excludedReadingCount == 1 ? 'reading is' : 'readings are'} '
                    'flagged and left out of these figures. They are still in '
                    'your history — Grid never deletes a reading, it just '
                    "doesn't average a suspect one into a baseline.",
              ),
            ],
            const SizedBox(height: Space.xl),
          ],

          SectionHeader(
            title: 'Where the units go',
            action: 'Appliances',
            onAction: () => context.push(Routes.appliances),
          ),
          const SizedBox(height: Space.md),

          if (model == null || model.attributions.isEmpty)
            InfoNote(
              message: 'Add what you run — a fridge, an air conditioner, a '
                  'pumping machine — and Grid can show which of them is '
                  'taking the units.',
              actions: [
                FilledButton.tonal(
                  onPressed: () => context.push(Routes.appliances),
                  child: const Text('Add appliances'),
                ),
              ],
            )
          else
            AttributionList(model: model, hasMeasuredSupply: hasSupply),

          const SizedBox(height: Space.xxxl),
        ],
      ),
    );
  }
}

class _WindowPicker extends StatelessWidget {
  const _WindowPicker({required this.days, required this.onChanged});

  final int days;
  final ValueChanged<int> onChanged;

  static const _options = [7, 30, 90];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Row(
      children: [
        for (final option in _options) ...[
          Expanded(
            child: Semantics(
              selected: option == days,
              button: true,
              child: Material(
                color: option == days ? c.brandSoft : c.surfaceRaised,
                borderRadius: Radii.smAll,
                child: InkWell(
                  borderRadius: Radii.smAll,
                  onTap: () => onChanged(option),
                  child: Container(
                    height: Targets.min - 8,
                    alignment: Alignment.center,
                    child: Text(
                      '$option days',
                      style: t.label.copyWith(
                        color: option == days ? c.brand : c.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (option != _options.last) const SizedBox(width: Space.sm),
        ],
      ],
    );
  }
}

class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.showCost,
    required this.canShowCost,
    required this.onChanged,
  });

  final bool showCost;
  final bool canShowCost;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Row(
      children: [
        Flexible(
          child: Text(
            showCost ? 'What it cost' : 'What you used',
            style: t.title.copyWith(color: c.textPrimary),
          ),
        ),
        const Spacer(),
        if (canShowCost)
          TextButton(
            onPressed: () => onChanged(!showCost),
            child: Text(showCost ? 'Show units' : 'Show naira'),
          ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: Radii.mdAll,
        border: Border.all(color: c.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: t.figure.copyWith(color: c.textPrimary)),
          const SizedBox(height: Space.xs),
          Text(label, style: t.caption.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}
