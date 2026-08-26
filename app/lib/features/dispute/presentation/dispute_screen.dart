import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/services/dispute_pack_engine.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../../shared/widgets/selectable_card.dart';
import '../../meter/application/meter_providers.dart';
import '../application/dispute_providers.dart';

/// Choose what the pack argues, and over what period.
///
/// The eligibility result is shown against the choice as it is made, rather
/// than at the end. A user who assembles a pack and is told at the last step
/// that a fortnight of data is required has been wasted; a user told at the
/// first step knows what to do about it.
class DisputeScreen extends ConsumerWidget {
  const DisputeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    if (meter == null) {
      return const GridScaffold(title: 'Dispute pack', body: SizedBox.shrink());
    }

    final c = context.colors;
    final t = context.type;
    final draft = ref.watch(packDraftProvider);
    final eligibility = ref.watch(packEligibilityProvider(meter.id));

    return GridScaffold(
      title: 'Dispute pack',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          Text(
            'A pack is a document you can hand over: what you were promised, '
            'what you recorded, and how complete the record is. Grid states '
            'the gaps in it as plainly as the figures.',
            style: t.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.xl),

          Text('What is this about?',
              style: t.title.copyWith(color: c.textPrimary)),
          const SizedBox(height: Space.md),
          for (final kind in PackKind.values) ...[
            SelectableCard(
              title: kind.label,
              subtitle: kind.description,
              selected: draft.kind == kind,
              onTap: () =>
                  ref.read(packDraftProvider.notifier).setKind(kind),
            ),
            const SizedBox(height: Space.sm),
          ],

          const SizedBox(height: Space.lg),
          Text('Over what period?',
              style: t.title.copyWith(color: c.textPrimary)),
          const SizedBox(height: Space.md),
          Row(
            children: [
              for (final days in const [30, 60, 90, 365]) ...[
                Expanded(
                  child: Semantics(
                    selected: draft.periodDays == days,
                    button: true,
                    child: Material(
                      color: draft.periodDays == days
                          ? c.brandSoft
                          : c.surfaceRaised,
                      borderRadius: Radii.smAll,
                      child: InkWell(
                        borderRadius: Radii.smAll,
                        onTap: () => ref
                            .read(packDraftProvider.notifier)
                            .setPeriod(days),
                        child: Container(
                          height: Targets.min,
                          alignment: Alignment.center,
                          child: Text(
                            days == 365 ? '1 year' : '$days d',
                            style: t.label.copyWith(
                              color: draft.periodDays == days
                                  ? c.brand
                                  : c.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (days != 365) const SizedBox(width: Space.sm),
              ],
            ],
          ),

          const SizedBox(height: Space.xl),
          if (eligibility is PackBlocked)
            InfoNote(
              tone: NoteTone.warning,
              icon: Icons.info_outline_rounded,
              message: eligibility.detail,
            )
          else if (eligibility is PackReady)
            const InfoNote(
              icon: Icons.check_circle_outline_rounded,
              message: 'There is enough record for this pack. The next screen '
                  'shows exactly what will be in it before anything is made.',
            ),

          const SizedBox(height: Space.xxxl),
        ],
      ),
      bottom: FilledButton(
        onPressed: eligibility is PackReady
            ? () => context.push(Routes.disputeReview)
            : null,
        child: const Text('Review what goes in'),
      ),
    );
  }
}
