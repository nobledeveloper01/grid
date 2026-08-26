import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router.dart';
import '../../../domain/services/band_adherence_engine.dart';
import '../../../domain/services/compliance_engine.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';
import '../application/supply_controller.dart';
import '../widgets/band_adherence_card.dart';

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
    final adherence = ref.watch(bandAdherenceProvider(meter.id));
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
          if (adherence != null) ...[
            BandAdherenceCard(adherence: adherence),
            if (adherence is AdherenceShortfall) ...[
              const SizedBox(height: Space.md),
              // The forward path. A screen that establishes a shortfall and
              // then leaves the user to work out what to do with it has done
              // the hard part and stopped one step short of the point.
              SizedBox(
                width: double.infinity,
                // Outlined, not filled. The bottom bar already holds the
                // one primary action on this screen, and two solid amber
                // buttons in view at once means neither is primary.
                child: SizedBox(
                  height: Targets.control,
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(Routes.dispute),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Build a dispute pack'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: Space.lg),
          ] else ...[
            // No band on the meter, so there is nothing to hold the DisCo
            // to. Still show what was measured — the log is worth keeping
            // either way.
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
                    'AVERAGE OVER 30 DAYS',
                    style: t.label
                        .copyWith(color: c.textSecondary, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    formatHours(summary.rollingAverageHours),
                    style: t.display.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(height: Space.md),
                  Text(
                    'Based on ${summary.usableDayCount} days with enough '
                    'data, covering ${formatPercent(summary.coverage)} of '
                    'the period.',
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
            for (final day in days) _DayRow(day: day, now: now),

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
  const _DayRow({required this.day, required this.now});

  final DailySupply day;
  final DateTime now;

  /// Today is scored against a full 24 hours like every other day, which is
  /// correct for compliance and wrong on screen: at 03:00 a perfectly
  /// observed morning has 12% coverage and renders as "No data". The day is
  /// not missing, it is in progress, and saying so is the difference between
  /// a log that looks broken every morning and one that does not.
  bool get _isToday =>
      day.date.year == now.year &&
      day.date.month == now.month &&
      day.date.day == now.day;

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
              _isToday
                  ? 'Today'
                  : '${weekdayName(day.date).substring(0, 3)} '
                      '${day.date.day}',
              style: t.caption.copyWith(
                color: _isToday ? c.textPrimary : c.textSecondary,
              ),
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
                      // On today, the remaining minutes have not happened
                      // yet. Painting them as unobserved would claim a gap
                      // in the record where there is only a clock.
                      child: ColoredBox(
                        color: _isToday ? c.track : c.supplyUnknown,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.md),
          SizedBox(
            width: 92,
            child: Text(
              switch ((_isToday, day.isUsable)) {
                (true, _) => '${formatHours(day.hours)} so far',
                (false, true) => formatHours(day.hours),
                (false, false) => 'No data',
              },
              textAlign: TextAlign.right,
              style: t.caption.copyWith(
                color: _isToday
                    ? c.textSecondary
                    : day.isUsable
                        ? c.textPrimary
                        : c.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
