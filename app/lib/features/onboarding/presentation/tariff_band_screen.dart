import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/providers.dart';
import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../features/meter/application/meter_providers.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../../shared/widgets/selectable_card.dart';
import '../application/onboarding_controller.dart';

class TariffBandScreen extends ConsumerStatefulWidget {
  const TariffBandScreen({super.key});

  @override
  ConsumerState<TariffBandScreen> createState() => _TariffBandScreenState();
}

class _TariffBandScreenState extends ConsumerState<TariffBandScreen> {
  bool _dontKnow = false;
  double _estimatedHours = 12;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final draft = ref.watch(onboardingControllerProvider);
    final table = ref.watch(tariffTableProvider).value;
    final t = context.type;
    final c = context.colors;

    final estimated = table?.estimateBand(_estimatedHours);

    return GridScaffold(
      step: 3,
      totalSteps: 3,
      body: ListView(
        children: [
          const SizedBox(height: Space.xl),
          Text('Which band are you on?', style: t.headline),
          const SizedBox(height: Space.sm),
          Text(
            'Your band sets your rate — and how many hours of power you are '
            'promised each day.',
            style: t.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.xl),
          if (!_dontKnow) ...[
            for (final band in TariffBand.values) ...[
              SelectableCard(
                title: 'Band ${band.label}',
                subtitle: band.commitment,
                selected: draft.band == band,
                trailing: table == null
                    ? null
                    : Text(
                        table.rateFor(draft.disco ?? DisCo.other, band)
                                ?.format() ??
                            '',
                        style: t.caption.copyWith(color: c.textSecondary),
                      ),
                onTap: () => ref
                    .read(onboardingControllerProvider.notifier)
                    .setBand(band),
              ),
              const SizedBox(height: Space.sm),
            ],
            const SizedBox(height: Space.md),
            TextButton(
              onPressed: () => setState(() => _dontKnow = true),
              child: const Text("I don't know my band"),
            ),
          ] else ...[
            Text(
              'Roughly how many hours of power do you get a day?',
              style: t.bodyStrong,
            ),
            const SizedBox(height: Space.lg),
            Text(
              '${_estimatedHours.round()} hours',
              style: t.display.copyWith(color: c.accent),
            ),
            Slider(
              value: _estimatedHours,
              min: 0,
              max: 24,
              divisions: 24,
              label: '${_estimatedHours.round()}h',
              onChanged: (v) => setState(() => _estimatedHours = v),
            ),
            const SizedBox(height: Space.lg),
            if (estimated != null)
              InfoNote(
                tone: NoteTone.estimate,
                message: 'That looks like Band ${estimated.label}. This is an '
                    'estimate — you can correct it any time in settings, and '
                    'Grid will tell you if your readings suggest otherwise.',
              ),
            const SizedBox(height: Space.md),
            TextButton(
              onPressed: () => setState(() => _dontKnow = false),
              child: const Text('Choose my band instead'),
            ),
          ],
          const SizedBox(height: Space.xxl),
        ],
      ),
      bottom: FilledButton(
        onPressed: _saving ? null : () => _finish(estimated),
        child: _saving
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Done'),
      ),
    );
  }

  Future<void> _finish(TariffBand? estimated) async {
    setState(() => _saving = true);
    final controller = ref.read(onboardingControllerProvider.notifier);
    if (_dontKnow && estimated != null) controller.setBand(estimated);

    final id = await controller.commit();
    if (!mounted) return;
    ref.read(selectedMeterIdProvider.notifier).select(id);
    context.go(Routes.onboardingFirstValue);
  }
}
