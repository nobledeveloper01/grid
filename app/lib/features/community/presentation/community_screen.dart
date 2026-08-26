import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/outage_map_engine.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';

final outageMapEngineProvider =
    Provider<OutageMapEngine>((ref) => const OutageMapEngine());

/// What this household would contribute to a community picture.
final contributionProvider =
    Provider.family<ContributionResult?, String>((ref, meterId) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == meterId)
      .firstOrNull;
  if (meter == null) return null;

  final events = ref.watch(supplyEventsProvider(meterId)).value;
  if (events == null) return null;

  final now = ref.watch(clockProvider)();
  return ref.watch(outageMapEngineProvider).prepare(
        lga: meter.lga,
        disco: meter.disco,
        band: meter.tariffBand,
        events: events,
        windowStart: now.subtract(const Duration(days: 30)),
        windowEnd: now,
        now: now,
      );
});

/// Pooling one household's log with its neighbours'.
///
/// Phase 7. One household's outage record proves that household was out;
/// several on the same feeder saying the same thing about the same hours prove
/// the *feeder* was out, which is a materially stronger claim and one nobody
/// can make alone.
///
/// The screen is mostly about consent, because the interesting part of this
/// feature is what it refuses to send.
class CommunityScreen extends ConsumerWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    if (meter == null) {
      return const GridScaffold(title: 'Your area', body: SizedBox.shrink());
    }

    final c = context.colors;
    final t = context.type;
    final contribution = ref.watch(contributionProvider(meter.id));
    final engine = ref.watch(outageMapEngineProvider);

    return GridScaffold(
      title: 'Your area',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          Text(
            'Your log proves your house was out. Several houses on the same '
            'feeder, saying the same thing about the same hours, prove the '
            'feeder was out — and that is a case no one household can make '
            'alone.',
            style: t.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.xl),

          switch (contribution) {
            null => const InfoNote(
                message: 'Grid is still reading your log.',
              ),
            ContributionBlocked(:final detail) => InfoNote(
                icon: Icons.info_outline_rounded,
                message: detail,
              ),
            ContributionReady(:final reports) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Panel(
                    title: 'WHAT WOULD BE SENT',
                    tone: c.textSecondary,
                    lines: engine.describe(reports),
                  ),
                  const SizedBox(height: Space.md),
                  _Panel(
                    title: 'WHAT NEVER LEAVES THIS PHONE',
                    tone: c.supplyOn,
                    lines: engine.describeWithheld(),
                  ),
                  const SizedBox(height: Space.lg),
                  Text(
                    'This list is generated from the payload itself, not '
                    'written separately — so it cannot drift from what would '
                    'actually be sent.',
                    style: t.caption.copyWith(color: c.textTertiary),
                  ),
                  const SizedBox(height: Space.xl),

                  // The pooled view, built from this household alone until
                  // there is a server to pool with. Shown rather than hidden,
                  // because it makes the shape of the answer concrete before
                  // anybody agrees to contribute to it.
                  _Pooled(reports: reports, engine: engine),
                ],
              ),
          },

          const SizedBox(height: Space.xl),
          const InfoNote(
            icon: Icons.cloud_off_rounded,
            message: 'Nothing is shared yet. Pooling needs a server, and Grid '
                'does not have one for this — the payload and the refusals '
                'are built and tested, and the sending is not.',
          ),
          const SizedBox(height: Space.xxxl),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.tone,
    required this.lines,
  });

  final String title;
  final Color tone;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: Radii.mdAll,
        border: Border.all(color: c.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: t.caption
                  .copyWith(color: tone, letterSpacing: 0.6, fontSize: 10)),
          const SizedBox(height: Space.sm),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text('· $line',
                  style: t.caption.copyWith(color: c.textSecondary)),
            ),
        ],
      ),
    );
  }
}

class _Pooled extends StatelessWidget {
  const _Pooled({required this.reports, required this.engine});

  final List<OutageReport> reports;
  final OutageMapEngine engine;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final pooled = engine.aggregate(reports).take(7).toList();
    if (pooled.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${reports.first.lga}, day by day',
            style: t.title.copyWith(color: c.textPrimary)),
        const SizedBox(height: Space.sm),
        Text(
          'As it would look once your neighbours contribute. Right now every '
          'figure rests on one log — yours — which is why none of them is '
          'marked as representative.',
          style: t.caption.copyWith(color: c.textTertiary),
        ),
        const SizedBox(height: Space.md),
        for (final day in pooled)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    '${weekdayName(day.date).substring(0, 3)} '
                    '${day.date.day}',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                ),
                Expanded(
                  child: Text(
                    formatHours(day.medianHours),
                    style: t.figure.copyWith(color: c.textPrimary),
                  ),
                ),
                Text(
                  day.isCredible
                      ? '${day.households} households'
                      : '${day.households} '
                          '${day.households == 1 ? 'log' : 'logs'} — not '
                          'yet a feeder',
                  style: t.caption.copyWith(
                    color: day.isCredible ? c.supplyOn : c.textTertiary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
