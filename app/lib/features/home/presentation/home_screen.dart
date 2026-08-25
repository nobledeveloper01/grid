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
import '../../../shared/widgets/info_note.dart';
import '../../../shared/widgets/supply_strip.dart';
import '../../meter/application/meter_providers.dart';
import '../widgets/hero_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    final t = context.type;
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
    final now = ref.watch(clockProvider)();

    return GridScaffold(
      showBack: false,
      body: ListView(
        children: [
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(meter.label, style: t.title),
                    Text(
                      '${meter.disco.code}'
                      '${meter.tariffBand != null ? ' · Band ${meter.tariffBand!.label}' : ''}',
                      style: t.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => context.push(Routes.readingHistory),
                icon: const Icon(Icons.history),
                tooltip: 'Reading history',
              ),
            ],
          ),
          const SizedBox(height: Space.xl),

          // The hero: the one number that matters, chosen by meter type.
          const HeroCard(),

          const SizedBox(height: Space.xl),

          // Supply strip.
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Last 7 days', style: t.label),
              TextButton(
                onPressed: () => context.push(Routes.supplyTimeline),
                child: const Text('Power log'),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          SupplyStrip(days: week),

          if (compliance != null && compliance.canRaiseAlert) ...[
            const SizedBox(height: Space.lg),
            InfoNote(
              tone: NoteTone.warning,
              message: "You're on Band ${compliance.band.label}, which "
                  'promises ${compliance.band.committedHours} hours a day. '
                  "You've been getting "
                  '${formatHours(compliance.summary.rollingAverageHours)}.',
            ),
          ],

          const SizedBox(height: Space.xl),
          Text('Recent readings', style: t.label),
          const SizedBox(height: Space.sm),
          if (readings.isEmpty)
            InfoNote(
              message: meter.type.isReadable
                  ? 'No readings yet. Log one and Grid starts working.'
                  : "You have no meter to read, so tell Grid what you run "
                      'instead — it will work out what you actually use.',
            )
          else
            for (final r in readings.take(3))
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Container(
                  padding: const EdgeInsets.all(Space.lg),
                  decoration: BoxDecoration(
                    color: c.surfaceDim,
                    borderRadius: Radii.mdAll,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.value.format(), style: t.figure),
                            Text(
                              relativeTime(r.readAt, now: now),
                              style: t.caption
                                  .copyWith(color: c.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      if (r.excludedFromBaseline)
                        Icon(Icons.flag_outlined,
                            size: 18, color: c.warning),
                      if (r.source == ReadingSource.ocr)
                        Icon(Icons.camera_alt_outlined,
                            size: 18, color: c.textTertiary),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: Space.xxxl),
        ],
      ),
      // Both buttons are Expanded: the button themes set a full-width
      // minimum size, which is infinite width and blows up as a bare Row
      // child. Expanded gives them a bounded width to stretch into.
      bottom: Row(
        children: [
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              onPressed: () => context.push(Routes.manualEntry),
              icon: const Icon(Icons.add),
              label: const Text('Log reading'),
            ),
          ),
          if (meter.isPrepaid) ...[
            const SizedBox(width: Space.md),
            Expanded(
              flex: 2,
              child: SizedBox(
                height: Targets.outdoor,
                child: OutlinedButton(
                  onPressed: () => context.push(Routes.purchaseEntry),
                  child: const Text('Bought units'),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
