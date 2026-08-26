import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../application/split_providers.dart';

/// The links a landlord has just issued, one per household.
///
/// Its own route rather than a section on the split screen or a bottom sheet.
/// Appending rows to a scrolled list leaves the reader looking at whatever
/// their old offset now points at, and the sheet version came up with zero
/// height — both of which are layout problems a full screen simply does not
/// have.
class SplitLinksScreen extends ConsumerWidget {
  const SplitLinksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final issued = ref.watch(issuedStatementsProvider);

    return GridScaffold(
      title: 'Links to send',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          if (issued.isEmpty)
            const InfoNote(
              message: 'Nothing to send. Issue a split first.',
            )
          else ...[
            Text(
              'Each link opens only that household’s statement — and shows '
              'them the whole split, so they can check it rather than take '
              'it on trust. They stop working in 90 days.',
              style: t.body.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: Space.xl),
            for (final s in issued)
              Container(
                margin: const EdgeInsets.only(bottom: Space.md),
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(
                  color: c.surfaceRaised,
                  borderRadius: Radii.mdAll,
                  border: Border.all(color: c.outline),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.name,
                              style: t.body.copyWith(color: c.textPrimary)),
                          const SizedBox(height: 2),
                          Text(s.amount.format(),
                              style: t.figure
                                  .copyWith(color: c.textSecondary)),
                        ],
                      ),
                    ),
                    const SizedBox(width: Space.md),
                    FilledButton.tonal(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: '${s.name}, your electricity share for this '
                              'period: ${s.shareUrl}',
                        ),
                      ),
                      child: const Text('Send'),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: Space.xxxl),
        ],
      ),
      bottom: FilledButton(
        onPressed: () {
          ref.read(issuedStatementsProvider.notifier).clear();
          context.pop();
        },
        child: const Text('Done'),
      ),
    );
  }
}
