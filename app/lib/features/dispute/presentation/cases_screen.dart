import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/entities/dispute_case.dart';
import '../../../domain/services/dispute_pack_engine.dart';
import '../../../domain/services/escalation_engine.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';
import '../application/dispute_providers.dart';

/// Complaints in progress, and what each one is waiting for.
///
/// The count of days is the point. Most complaints die at the first office,
/// not because the case was weak but because nobody was counting and nobody
/// knew there was a step above it.
class CasesScreen extends ConsumerWidget {
  const CasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    if (meter == null) {
      return const GridScaffold(title: 'Cases', body: SizedBox.shrink());
    }

    final c = context.colors;
    final t = context.type;
    final cases = ref.watch(trackedCasesProvider(meter.id));
    final open = cases.where((x) => !x.caseRecord.isClosed).toList();
    final closed = cases.where((x) => x.caseRecord.isClosed).toList();

    return GridScaffold(
      title: 'Cases',
      body: cases.isEmpty
          ? ListView(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              children: const [
                InfoNote(
                  icon: Icons.folder_open_rounded,
                  message: 'Nothing open. When you make a dispute pack and '
                      'hand it over, Grid opens a case here and counts the '
                      'days for you — including the day the next step '
                      'becomes available.',
                ),
              ],
            )
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              children: [
                for (final tracked in open)
                  _CaseCard(tracked: tracked),
                if (closed.isNotEmpty) ...[
                  const SizedBox(height: Space.lg),
                  Text(
                    'CLOSED',
                    style: t.label
                        .copyWith(color: c.textTertiary, letterSpacing: 0.8),
                  ),
                  const SizedBox(height: Space.md),
                  for (final tracked in closed)
                    _CaseCard(tracked: tracked),
                ],
                const SizedBox(height: Space.xxxl),
              ],
            ),
      bottom: FilledButton.icon(
        onPressed: () => context.push(Routes.dispute),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Start a new pack'),
      ),
    );
  }
}

class _CaseCard extends ConsumerWidget {
  const _CaseCard({required this.tracked});

  final TrackedCase tracked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final record = tracked.caseRecord;
    final state = tracked.state;
    final controller = ref.read(caseControllerProvider.notifier);

    final kind = PackKind.values
        .where((k) => k.name == record.kind)
        .firstOrNull;

    final accent = switch (record.status) {
      CaseStatus.resolved => c.supplyOn,
      CaseStatus.abandoned => c.textTertiary,
      _ => state.canEscalate ? c.warning : c.brand,
    };

    return Container(
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: Radii.mdAll,
        border: Border.all(color: c.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  kind?.label ?? 'Dispute',
                  style: t.title.copyWith(color: c.textPrimary),
                ),
              ),
              Flexible(
                child: Text(
                  _statusLabel(record.status),
                  maxLines: 2,
                  textAlign: TextAlign.right,
                  style: t.caption.copyWith(color: accent),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xs),
          Text(
            '${friendlyDate(record.periodStart, now: record.createdAt)} to '
            '${friendlyDate(record.periodEnd, now: record.createdAt)}',
            style: t.caption.copyWith(color: c.textTertiary),
          ),

          const SizedBox(height: Space.md),
          Container(
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: c.surfaceDim,
              borderRadius: Radii.smAll,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOW AT: ${record.step.label.toUpperCase()}',
                  style: t.caption
                      .copyWith(color: c.textSecondary, letterSpacing: 0.6),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  record.step.guidance,
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
                if (record.reference != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(
                    'Their reference: ${record.reference}',
                    style: t.caption.copyWith(color: c.textSecondary),
                  ),
                ],
              ],
            ),
          ),

          if (!record.isClosed) ...[
            const SizedBox(height: Space.md),
            _Timing(state: state),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: [
                if (record.submittedAt == null)
                  FilledButton.tonal(
                    onPressed: () => _askReference(context, ref, record),
                    child: const Text('I handed it over'),
                  ),
                if (state.canEscalate)
                  FilledButton.tonal(
                    onPressed: () => controller.escalate(record),
                    child: Text('Take it to ${record.step.next!.label}'),
                  ),
                if (record.packPath != null)
                  OutlinedButton(
                    onPressed: () => SharePlus.instance.share(
                      ShareParams(
                        files: [
                          XFile(record.packPath!,
                              mimeType: 'application/pdf'),
                        ],
                      ),
                    ),
                    child: const Text('Send the pack again'),
                  ),
                TextButton(
                  onPressed: () =>
                      controller.setStatus(record, CaseStatus.resolved),
                  child: const Text('Resolved'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _statusLabel(CaseStatus s) => switch (s) {
        CaseStatus.open => 'Not yet handed over',
        CaseStatus.awaitingResponse => 'Waiting',
        CaseStatus.resolved => 'Resolved',
        CaseStatus.abandoned => 'Dropped',
      };

  Future<void> _askReference(
    BuildContext context,
    WidgetRef ref,
    DisputeCase record,
  ) async {
    final controller = TextEditingController();
    final reference = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radii.lg),
      ),
      builder: (sheet) => Padding(
        padding: EdgeInsets.only(
          left: Space.xl,
          right: Space.xl,
          top: Space.xl,
          bottom: MediaQuery.viewInsetsOf(sheet).bottom + Space.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Did they give you a reference?',
                style: sheet.type.headline),
            const SizedBox(height: Space.sm),
            Text(
              'A complaint number, a receipt, the name of whoever took it — '
              'anything with a date on it. Without one, the next step starts '
              'the clock again from nothing.',
              style: sheet.type.caption
                  .copyWith(color: sheet.colors.textTertiary),
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'Optional'),
            ),
            const SizedBox(height: Space.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(sheet).pop(controller.text),
                child: const Text('Start the clock'),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (reference == null) return;
    await ref.read(caseControllerProvider.notifier).markSubmitted(
          record,
          reference: reference.trim().isEmpty ? null : reference.trim(),
        );
  }
}

class _Timing extends StatelessWidget {
  const _Timing({required this.state});

  final EscalationState state;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    if (state.submittedAt == null) {
      return Text(
        'The clock starts when you hand it over.',
        style: t.caption.copyWith(color: c.textTertiary),
      );
    }

    final elapsed = state.daysElapsed ?? 0;
    final remaining = state.daysRemaining;

    if (remaining == null) {
      return Text(
        '$elapsed ${elapsed == 1 ? 'day' : 'days'} since you submitted it.',
        style: t.body.copyWith(color: c.textSecondary),
      );
    }

    if (state.canEscalate) {
      return Text(
        '$elapsed days with no resolution. You can take this to '
        '${state.step.next!.label} now.',
        style: t.bodyStrong.copyWith(color: c.warning),
      );
    }

    final wait = state.step.waitDays!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Day $elapsed of $wait. $remaining to go before '
          '${state.step.next!.label} opens.',
          style: t.body.copyWith(color: c.textSecondary),
        ),
        const SizedBox(height: Space.sm),
        ClipRRect(
          borderRadius: Radii.smAll,
          child: LinearProgressIndicator(
            value: (elapsed / wait).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: c.track,
            valueColor: AlwaysStoppedAnimation(c.brand),
          ),
        ),
      ],
    );
  }
}
