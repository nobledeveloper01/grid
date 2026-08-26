import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'package:go_router/go_router.dart';

import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/band_adherence_engine.dart';
import '../../../domain/services/dispute_pack_engine.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';
import '../application/dispute_providers.dart';

/// Everything that will be in the pack, before it exists.
///
/// The excluded readings are shown here with the same weight as the included
/// ones. A user who is going to be asked about a flagged reading at a
/// counter should meet it here first, not there.
class PackReviewScreen extends ConsumerStatefulWidget {
  const PackReviewScreen({super.key});

  @override
  ConsumerState<PackReviewScreen> createState() => _PackReviewScreenState();
}

class _PackReviewScreenState extends ConsumerState<PackReviewScreen> {
  final _narrative = TextEditingController();
  final _amount = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _narrative.dispose();
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meter = ref.watch(selectedMeterProvider);
    if (meter == null) {
      return const GridScaffold(title: 'Review', body: SizedBox.shrink());
    }

    final c = context.colors;
    final t = context.type;
    final pack = ref.watch(disputePackProvider(meter.id));

    if (pack == null) {
      return const GridScaffold(
        title: 'Review',
        body: Center(
          child: InfoNote(
            message: 'There is not enough record for this pack yet.',
          ),
        ),
      );
    }

    return GridScaffold(
      title: 'Review',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          _Block(
            title: pack.kind.label,
            child: Text(
              '${friendlyDate(pack.periodStart, now: pack.generatedAt)} to '
              '${friendlyDate(pack.periodEnd, now: pack.generatedAt)} · '
              '${pack.days} days',
              style: t.body.copyWith(color: c.textSecondary),
            ),
          ),

          if (pack.adherence case final AdherenceShortfall a) ...[
            const SizedBox(height: Space.md),
            _Block(
              title: 'The claim',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${formatHours(a.shortfallHours)} a day short of the '
                    'Band ${a.billedBand.label} promise.',
                    style: t.bodyStrong.copyWith(color: c.warning),
                  ),
                  if (a.overpayment != null && !a.overpayment!.isZero) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      '${a.overpayment!.format()} in rate difference over '
                      '${a.energy.format()}.',
                      style: t.body.copyWith(color: c.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ],

          const SizedBox(height: Space.md),
          _Block(
            title: 'How complete it is',
            child: Text(
              'Readings span ${formatPercent(pack.readingCoverage)} of the '
              'period. The power log observed '
              '${formatPercent(pack.supplyCoverage)} of it. Both figures are '
              'printed in the pack — Grid states its gaps rather than '
              'letting somebody else find them.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
          ),

          const SizedBox(height: Space.md),
          _Block(
            title: '${pack.included.length} readings included',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in pack.included.take(4))
                  _EvidenceRow(item: e, now: pack.generatedAt),
                if (pack.included.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xs),
                    child: Text(
                      'and ${pack.included.length - 4} more',
                      style: t.caption.copyWith(color: c.textTertiary),
                    ),
                  ),
              ],
            ),
          ),

          if (pack.excluded.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            _Block(
              title: '${pack.excluded.length} excluded, with reasons',
              tone: c.warning,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final e in pack.excluded) ...[
                    _EvidenceRow(item: e, now: pack.generatedAt),
                    Padding(
                      padding: const EdgeInsets.only(bottom: Space.sm),
                      child: Text(
                        e.exclusionReason ?? '',
                        style: t.caption.copyWith(color: c.textTertiary),
                      ),
                    ),
                  ],
                  Text(
                    'These stay in your history. The pack lists them and says '
                    'why they are set aside, because a pack that quietly drops '
                    'the awkward readings can be accused of exactly that.',
                    style: t.caption.copyWith(color: c.textTertiary),
                  ),
                ],
              ),
            ),
          ],

          if (pack.kind == PackKind.estimatedBill) ...[
            const SizedBox(height: Space.md),
            _Block(
              title: 'The amount you were billed',
              child: TextField(
                controller: _amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  prefixText: '${Naira.naira} ',
                  hintText: 'Optional',
                ),
                onChanged: (v) {
                  final n = double.tryParse(v.replaceAll(',', ''));
                  ref.read(packDraftProvider.notifier).setAmount(
                      n == null ? null : Naira.fromNaira(n));
                },
              ),
            ),
          ],

          const SizedBox(height: Space.md),
          _Block(
            title: 'Anything you want to add',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Printed word for word. Grid does not rewrite it.',
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
                const SizedBox(height: Space.sm),
                TextField(
                  controller: _narrative,
                  maxLines: 4,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'What happened, in your own words.',
                  ),
                  onChanged: (v) =>
                      ref.read(packDraftProvider.notifier).setNarrative(v),
                ),
              ],
            ),
          ),

          const SizedBox(height: Space.xxxl),
        ],
      ),
      bottom: Row(
        children: [
          // Icon only. "Preview" beside an icon wrapped to two lines at this
          // width, and a button whose own label breaks in half does not read
          // as a finished screen.
          SizedBox(
            width: Targets.control,
            height: Targets.control,
            child: IconButton.outlined(
              onPressed: _busy ? null : () => _preview(meter.id),
              tooltip: 'Preview the pack',
              icon: const Icon(Icons.visibility_outlined, size: 20),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            child: FilledButton.icon(
              onPressed: _busy ? null : () => _share(meter.id),
              icon: const Icon(Icons.ios_share_rounded, size: 18),
              label: Text(_busy ? 'Preparing…' : 'Make the pack'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _preview(String meterId) async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(packFileProvider(meterId).future);
      if (!mounted) return;
      await Printing.layoutPdf(onLayout: (_) => file.bytes);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share(String meterId) async {
    setState(() => _busy = true);
    try {
      final file = await ref.read(packFileProvider(meterId).future);
      final pack = ref.read(disputePackProvider(meterId));
      if (!mounted || pack == null) return;

      // Nothing has left the device up to this point, and nothing does now
      // unless the user picks somewhere to send it.
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          subject: 'Electricity dispute pack',
        ),
      );

      // A case opens on share, not on preview: a preview is somebody
      // checking their own work, and a case list full of drafts is a case
      // list nobody trusts.
      await ref
          .read(caseControllerProvider.notifier)
          .open(pack: pack, packPath: file.path);
      if (!mounted) return;
      // `go` alone would leave the cases screen with nothing to go back to.
      // Reset to home first, then push, so the back gesture lands somewhere.
      context.go(Routes.home);
      context.push(Routes.cases);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child, this.tone});

  final String title;
  final Widget child;
  final Color? tone;

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
        border: Border.all(
          color: tone?.withValues(alpha: 0.35) ?? c.outline,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: t.label.copyWith(
              color: tone ?? c.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: Space.sm),
          child,
        ],
      ),
    );
  }
}

class _EvidenceRow extends StatelessWidget {
  const _EvidenceRow({required this.item, required this.now});

  final EvidenceItem item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item.reading.value.formatValue(),
              style: t.figure.copyWith(
                color: item.isIncluded ? c.textPrimary : c.textTertiary,
                decoration:
                    item.isIncluded ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
          if (item.reading.photoSha256 != null)
            Padding(
              padding: const EdgeInsets.only(right: Space.sm),
              child: Icon(Icons.image_outlined, size: 14, color: c.textTertiary),
            ),
          Flexible(
            child: Text(
              friendlyDate(item.reading.readAt, now: now),
              maxLines: 2,
              textAlign: TextAlign.right,
              style: t.caption.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}
