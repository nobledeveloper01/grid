import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/providers.dart';
import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/widgets/figure.dart';
import '../../../shared/widgets/info_note.dart';
import '../../../shared/widgets/stat_tile.dart';
import '../../../shared/widgets/supply_strip.dart';
import '../../meter/application/meter_providers.dart';
import '../../supply/application/supply_inference_controller.dart';
import '../../../shared/charts/trend_chart.dart';
import '../../budget/presentation/budget_card.dart';
import '../../dispute/application/dispute_providers.dart';
import '../../insights/application/insights_providers.dart';
import '../../reminders/application/reminder_providers.dart';
import '../widgets/hero_card.dart';
import '../widgets/section_header.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    final c = context.colors;

    // Meters come from local storage and arrive in milliseconds. There is no
    // network here, so there is no spinner — just a frame or two of nothing
    // before the redirect sends a first-run user to onboarding.
    if (meter == null) {
      return const GridScaffold(body: SizedBox.shrink());
    }

    final readings = ref.watch(readingsProvider(meter.id)).value ?? const [];
    final week = ref.watch(weekSupplyProvider(meter.id));
    final compliance = ref.watch(complianceProvider(meter.id));
    final rate = ref.watch(effectiveRateProvider(meter.id));
    final now = ref.watch(clockProvider)();

    // Charging-state inference runs while the home screen is mounted. It is
    // an inference, it is debounced, and it stops entirely for a user who
    // told us they are on an inverter.
    ref.watch(supplyInferenceProvider);

    // A band-shortfall alert, at most once per cooldown. The hysteresis is
    // in the engine; this is only the thing that calls it.
    ref.watch(complianceAlertProvider(meter.id));

    return GridScaffold(
      showBack: false,
      padded: false,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _Greeting(meterLabel: meter.label)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Space.lg,
              0,
              Space.lg,
              Space.xxxl + Space.xxl,
            ),
            sliver: SliverList.list(
              children: [
                const HeroCard(),
                const SizedBox(height: Space.md),
                BudgetCard(meterId: meter.id),
                const SizedBox(height: Space.xl),

                // At-a-glance figures.
                Row(
                  children: [
                    Expanded(
                      child: StatTile(
                        label: 'Tariff band',
                        value: meter.tariffBand == null
                            ? '—'
                            : 'Band ${meter.tariffBand!.label}',
                        caption: rate?.format(),
                        isNumeric: false,
                        icon: Icons.local_offer_rounded,
                        tone: c.accent,
                        onTap: () => context.push(Routes.supplyTimeline),
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: StatTile(
                        label: 'Readings logged',
                        value: '${readings.length}',
                        caption: readings.isEmpty
                            ? 'None yet'
                            : relativeTime(readings.first.readAt, now: now),
                        icon: Icons.timeline_rounded,
                        tone: c.supplyOn,
                        onTap: () => context.push(Routes.readingHistory),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: Space.xl),

                SectionHeader(
                  title: 'Power this week',
                  action: 'Power log',
                  onAction: () => context.push(Routes.supplyTimeline),
                ),
                const SizedBox(height: Space.md),
                SupplyStrip(days: week),

                if (compliance != null && compliance.canRaiseAlert) ...[
                  const SizedBox(height: Space.lg),
                  InfoNote(
                    tone: NoteTone.warning,
                    icon: Icons.gavel_rounded,
                    message: "You're on Band ${compliance.band.label}, which "
                        'promises ${compliance.band.committedHours} hours a '
                        "day. You've been getting "
                        '${formatHours(compliance.summary.rollingAverageHours)}.',
                    actions: [
                      OutlinedButton(
                        onPressed: () => context.push(Routes.supplyTimeline),
                        child: const Text('See the log'),
                      ),
                      FilledButton.tonal(
                        onPressed: () => context.push(Routes.dispute),
                        child: const Text('Build a pack'),
                      ),
                    ],
                  ),
                ],

                _OpenCases(meterId: meter.id),
                const _ReminderOffer(),

                const SizedBox(height: Space.xl),
                SectionHeader(
                  title: 'What you used',
                  action: 'Insights',
                  onAction: () => context.push(Routes.insights),
                ),
                const SizedBox(height: Space.md),
                _UsagePreview(meterId: meter.id),

                const SizedBox(height: Space.xl),
                SectionHeader(
                  title: 'Recent readings',
                  action: readings.isEmpty ? null : 'See all',
                  onAction: readings.isEmpty
                      ? null
                      : () => context.push(Routes.readingHistory),
                ),
                const SizedBox(height: Space.md),

                if (readings.isEmpty)
                  InfoNote(
                    icon: Icons.speed_rounded,
                    message: meter.type.isReadable
                        ? 'No readings yet. Log one and Grid starts working.'
                        : 'You have no meter to read, so tell Grid what you '
                            'run instead — it will work out what you actually '
                            'use.',
                  )
                else
                  for (final (i, r) in readings.take(3).indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: _ReadingRow(
                        value: r.value.formatValue(),
                        when: relativeTime(r.readAt, now: now),
                        isFlagged: r.excludedFromBaseline,
                        source: r.source,
                        index: i,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
      bottom: Row(
        children: [
          Expanded(
            flex: 3,
            child: Consumer(
              builder: (context, ref, _) {
                // Route to the camera only where recognition actually works.
                // Offering a camera button that falls straight through to
                // manual entry is worse than not offering one.
                final ocr = ref.watch(ocrAvailableProvider).value ?? false;
                return FilledButton.icon(
                  onPressed: () => context.push(
                    ocr ? Routes.capture : Routes.manualEntry,
                  ),
                  icon: Icon(
                    ocr ? Icons.camera_alt_rounded : Icons.add_rounded,
                  ),
                  label: const Text('Log reading'),
                );
              },
            ),
          ),
          if (meter.isPrepaid) ...[
            const SizedBox(width: Space.md),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: Targets.control,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(Routes.purchaseEntry),
                  icon: const Icon(Icons.add_card_rounded, size: 18),
                  label: const Text('Units'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The one time Grid asks about reminders.
///
/// After the second reading, so the user has done the thing twice and can
/// see what it is for. Either answer is final — an app that asks again next
/// week has not taken the first one seriously.
class _ReminderOffer extends ConsumerWidget {
  const _ReminderOffer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(shouldOfferReminderProvider)) {
      return const SizedBox.shrink();
    }
    final controller = ref.read(reminderControllerProvider.notifier);

    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: InfoNote(
        icon: Icons.notifications_none_rounded,
        message: 'A reading near the same date each month is what lets Grid '
            'check a bill against your meter. Want a monthly reminder?',
        actions: [
          OutlinedButton(
            onPressed: controller.declineOffer,
            child: const Text('No thanks'),
          ),
          FilledButton.tonal(
            onPressed: () async {
              final granted =
                  await controller.enable(dayOfMonth: DateTime.now().day);
              if (!granted && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Notifications are off for Grid in your phone settings.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Yes, remind me'),
          ),
        ],
      ),
    );
  }
}

/// An open complaint, and what it is waiting for.
///
/// Surfaced on the home screen rather than buried in settings, because the
/// whole value of tracking a case is that somebody is counting the days —
/// and nobody counts days they have to go looking for.
class _OpenCases extends ConsumerWidget {
  const _OpenCases({required this.meterId});

  final String meterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final open = ref
        .watch(trackedCasesProvider(meterId))
        .where((x) => !x.caseRecord.isClosed)
        .toList();
    if (open.isEmpty) return const SizedBox.shrink();

    final first = open.first;
    final state = first.state;
    final waiting = state.daysElapsed;

    final line = switch ((waiting, state.canEscalate)) {
      (null, _) => 'Ready to hand over.',
      (final d, true) =>
        '$d days with no answer — you can take it higher now.',
      (final d, false) => 'Day $d at ${first.caseRecord.step.label}.',
    };

    return Padding(
      padding: const EdgeInsets.only(top: Space.xl),
      child: Material(
        color: c.surfaceRaised,
        borderRadius: Radii.mdAll,
        child: InkWell(
          borderRadius: Radii.mdAll,
          onTap: () => context.push(Routes.cases),
          child: Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              borderRadius: Radii.mdAll,
              border: Border.all(
                color: state.canEscalate
                    ? c.warning.withValues(alpha: 0.35)
                    : c.outline,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.folder_open_rounded,
                  size: 20,
                  color: state.canEscalate ? c.warning : c.textSecondary,
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        open.length == 1
                            ? 'One case open'
                            : '${open.length} cases open',
                        style: t.body.copyWith(color: c.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        line,
                        style: t.caption.copyWith(
                          color: state.canEscalate
                              ? c.warning
                              : c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded,
                    size: 18, color: c.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A glance at the last thirty days, linking to the full chart.
class _UsagePreview extends ConsumerWidget {
  const _UsagePreview({required this.meterId});

  final String meterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final points =
        ref.watch(consumptionTrendProvider((meterId: meterId, days: 30)));
    final series =
        ref.watch(consumptionSeriesProvider((meterId: meterId, days: 30)));

    if (points.length < 2) {
      return const InfoNote(
        icon: Icons.show_chart_rounded,
        message: 'Two readings and Grid can draw your usage. It only needs '
            'the number on the meter.',
      );
    }

    return Material(
      color: c.surfaceRaised,
      borderRadius: Radii.mdAll,
      child: InkWell(
        borderRadius: Radii.mdAll,
        onTap: () => context.push(Routes.insights),
        child: Padding(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    series == null
                        ? '—'
                        : Kwh.fromDouble(series.dailyMean).format(),
                    style: t.title.copyWith(color: c.textPrimary),
                  ),
                  const SizedBox(width: Space.xs),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'a day, last 30 days',
                      style: t.caption.copyWith(color: c.textSecondary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.sm),
              TrendChart(points: points, valueLabel: 'kWh', height: 86,
                  compact: true),
            ],
          ),
        ),
      ),
    );
  }
}

/// The page header, sitting on a warm wash so the screen does not open on a
/// flat white sheet.
class _Greeting extends ConsumerWidget {
  const _Greeting({required this.meterLabel});

  final String meterLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final meter = ref.watch(selectedMeterProvider);
    final now = ref.watch(clockProvider)();

    final greeting = switch (now.hour) {
      < 12 => 'Good morning',
      < 17 => 'Good afternoon',
      _ => 'Good evening',
    };

    return Container(
      decoration: BoxDecoration(gradient: c.washGradient),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.lg, Space.xl),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: t.caption.copyWith(
                    color: c.textSecondary,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Row(
                  children: [
                    Text(meterLabel, style: t.headline),
                    const SizedBox(width: Space.sm),
                    if (meter != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: c.accentSoft,
                          borderRadius: Radii.smAll,
                        ),
                        child: Text(
                          meter.disco.code,
                          style: t.caption.copyWith(
                            color: c.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          _RoundIconButton(
            icon: Icons.history_rounded,
            tooltip: 'Reading history',
            onPressed: () => context.push(Routes.readingHistory),
          ),
          const SizedBox(width: Space.sm),
          _RoundIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Settings',
            onPressed: () => context.push(Routes.settings),
          ),
        ],
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: c.surfaceRaised,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: Targets.min,
            height: Targets.min,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.outline),
            ),
            child: Icon(icon, size: 20, color: c.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _ReadingRow extends StatelessWidget {
  const _ReadingRow({
    required this.value,
    required this.when,
    required this.isFlagged,
    required this.source,
    required this.index,
  });

  final String value;
  final String when;
  final bool isFlagged;
  final ReadingSource source;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Motion.page + Motion.stagger * index,
      curve: Curves.easeOutCubic,
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 8), child: child),
      ),
      child: Container(
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: Radii.mdAll,
          border: Border.all(color: c.outline),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(Space.sm),
              decoration: BoxDecoration(
                color: c.brandSoft,
                borderRadius: Radii.smAll,
              ),
              child: Icon(
                switch (source) {
                  ReadingSource.ocr => Icons.center_focus_strong_rounded,
                  ReadingSource.manual => Icons.keyboard_rounded,
                  ReadingSource.imported => Icons.download_rounded,
                },
                size: 18,
                color: c.brandDeep,
              ),
            ),
            const SizedBox(width: Space.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Figure(value: value, unit: Kwh.unit),
                  Text(
                    when,
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ),
            ),
            if (isFlagged)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.sm,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: c.warningSoft,
                  borderRadius: Radii.smAll,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.flag_rounded, size: 12, color: c.warning),
                    const SizedBox(width: Space.xs),
                    Text(
                      'Flagged',
                      style: t.caption.copyWith(
                        color: c.warning,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
