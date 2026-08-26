import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/compliance_engine.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';
import '../application/supply_controller.dart';

/// The power log.
///
/// Coverage is displayed on every day and on the window as a whole. A day we
/// barely observed is shown as such rather than being interpolated into
/// whichever state would look better — a dispute pack built on a fabricated
/// timeline would be actively harmful.
class SupplyTimelineScreen extends ConsumerWidget {
  const SupplyTimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    final t = context.type;
    final c = context.colors;

    if (meter == null) {
      return const GridScaffold(title: 'Power log', body: SizedBox.shrink());
    }

    final events = ref.watch(supplyEventsProvider(meter.id)).value ?? const [];
    final compliance = ref.watch(complianceProvider(meter.id));
    final ongoing = ref.watch(ongoingSupplyProvider(meter.id));
    final now = ref.watch(clockProvider)();

    final summary = ref.watch(complianceEngineProvider).summarise(
          events: events,
          windowStart: now.subtract(const Duration(days: 29)),
          windowEnd: now,
          now: now,
        );
    final days = summary.days.reversed.toList();

    return GridScaffold(
      title: 'Power log',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          if (compliance != null) ...[
            Container(
              padding: const EdgeInsets.all(Space.xl),
              decoration: BoxDecoration(
                color: c.surfaceDim,
                borderRadius: Radii.lgAll,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Average over 30 days',
                    style: t.label.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    formatHours(summary.rollingAverageHours),
                    style: t.display.copyWith(
                      color: compliance.isBreach ? c.warning : c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    compliance.band.commitment,
                    style: t.body.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: Space.md),
                  // Coverage is stated plainly, always.
                  Text(
                    'Based on ${summary.usableDayCount} days with enough data. '
                    'This log covers ${formatPercent(summary.coverage)} of the '
                    'period.',
                    style: t.caption.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Space.lg),
          ],

          if (events.isEmpty)
            const InfoNote(
              message: "Grid hasn't logged any power yet. Tap the button "
                  'below when the power goes off or comes back, and your '
                  'record starts building.',
            )
          else
            for (final day in days) _DayRow(day: day),

          const SizedBox(height: Space.xxxl),
        ],
      ),
      bottom: FilledButton.icon(
        onPressed: () => ref
            .read(supplyControllerProvider.notifier)
            .toggle(meterId: meter.id),
        icon: Icon(
          ongoing?.state.name == 'available'
              ? Icons.flash_off_outlined
              : Icons.flash_on_outlined,
        ),
        label: Text(
          ongoing?.state.name == 'available'
              ? 'Power just went off'
              : 'Power is back',
        ),
      ),
    );
  }
}

class _DayRow extends StatelessWidget {
  const _DayRow({required this.day});

  final DailySupply day;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              '${weekdayName(day.date).substring(0, 3)} ${day.date.day}',
              style: t.caption.copyWith(color: c.textSecondary),
            ),
          ),
          Expanded(
            child: Container(
              height: 14,
              // The track keeps an all-unknown day visible as a row rather
              // than as a gap, and gives the coloured segments something to
              // sit in when they cover only part of the day.
              decoration: BoxDecoration(
                color: c.track,
                borderRadius: Radii.smAll,
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                // Stretch, not the default centre. A childless ColoredBox
                // sizes to the smallest constraint it is given, so under a
                // Row's default cross-axis alignment every segment collapsed
                // to zero height and the whole bar rendered invisible — the
                // data was correct, nothing threw, and the row simply looked
                // empty.
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (day.availableMinutes > 0)
                    Expanded(
                      flex: day.availableMinutes,
                      child: ColoredBox(color: c.supplyOn),
                    ),
                  if (day.unavailableMinutes > 0)
                    Expanded(
                      flex: day.unavailableMinutes,
                      child: ColoredBox(color: c.supplyOff),
                    ),
                  if (day.unknownMinutes > 0)
                    Expanded(
                      flex: day.unknownMinutes,
                      child: ColoredBox(color: c.supplyUnknown),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          SizedBox(
            width: 64,
            child: Text(
              day.isUsable ? formatHours(day.hours) : 'No data',
              textAlign: TextAlign.right,
              style: t.caption.copyWith(
                color: day.isUsable ? c.textPrimary : c.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
