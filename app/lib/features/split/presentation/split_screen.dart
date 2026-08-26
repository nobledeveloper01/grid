import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/router/router.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/services/allocation_engine.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../../shared/widgets/text_prompt_sheet.dart';
import '../../meter/application/meter_providers.dart';
import '../application/split_providers.dart';
import '../data/statement_client.dart';

/// One meter, several households, and arithmetic everybody can see.
///
/// Feature F11. This is the highest-frequency dispute in the market — monthly,
/// in every compound — and the one Grid can settle before it starts rather
/// than after. The landlord console in phase 6 does the same thing with a
/// server behind it; this does the ninety-percent version with none.
class SplitScreen extends ConsumerWidget {
  const SplitScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    if (meter == null) {
      return const GridScaffold(title: 'Split the bill', body: SizedBox.shrink());
    }

    final c = context.colors;
    final t = context.type;
    final occupants = ref.watch(occupantsProvider(meter.id)).value ?? const [];
    final rule = ref.watch(splitRuleProvider(meter.id)).value ?? SplitRule.equal;
    final allocation = ref.watch(allocationProvider(meter.id));
    final controller = ref.read(splitControllerProvider.notifier);

    return GridScaffold(
      title: 'Split the bill',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          if (occupants.isEmpty)
            const InfoNote(
              icon: Icons.groups_outlined,
              message: 'One meter, several households? Add everyone behind it '
                  'and Grid works out each share — and produces a receipt you '
                  'can send that shows the arithmetic, not just the answer.',
            )
          else ...[
            Text('How is it split?',
                style: t.title.copyWith(color: c.textPrimary)),
            const SizedBox(height: Space.md),
            for (final r in SplitRule.values) ...[
              _RuleRow(
                rule: r,
                selected: r == rule,
                onTap: () => controller.setRule(meter.id, r),
              ),
              const SizedBox(height: Space.sm),
            ],
            const SizedBox(height: Space.lg),
            if (allocation == null)
              const InfoNote(
                message: 'Grid needs a couple of readings before it can put a '
                    'figure on anybody’s share.',
              )
            else ...[
              _Shares(allocation: allocation, meterId: meter.id),
              const SizedBox(height: Space.md),
              _SendStatements(meterId: meter.id),
            ],
          ],

          const SizedBox(height: Space.lg),
          Text('Who is behind the meter',
              style: t.title.copyWith(color: c.textPrimary)),
          const SizedBox(height: Space.md),
          for (final o in occupants)
            _OccupantRow(
              occupant: o,
              rule: rule,
              onRemove: () => controller.remove(o.id),
            ),

          const SizedBox(height: Space.xxxl),
        ],
      ),
      bottom: FilledButton.icon(
        onPressed: () async {
          final name = await promptForText(
            context,
            title: 'Who else is on this meter?',
            hintText: 'Flat 2, or a name',
            confirmLabel: 'Add',
          );
          if (name == null || name.trim().isEmpty) return;
          await controller.saveOccupant(
            meterId: meter.id,
            name: name.trim(),
          );
        },
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Add a household'),
      ),
    );
  }
}

/// Send each household a link they can open with nothing.
///
/// The one outbound call in the application, and it happens because somebody
/// pressed this. The receipt PDF above works with no connection at all; this
/// is for the tenant who would rather have a page than a file.
class _SendStatements extends ConsumerStatefulWidget {
  const _SendStatements({required this.meterId});

  final String meterId;

  @override
  ConsumerState<_SendStatements> createState() => _SendStatementsState();
}

class _SendStatementsState extends ConsumerState<_SendStatements> {
  bool _busy = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final configured = ref.watch(serverConfiguredProvider);

    if (!configured) {
      return const InfoNote(
        icon: Icons.link_outlined,
        message: 'You can also send each household a link they open in a '
            'browser — no app, no account. Add your server address in '
            'Settings to turn that on.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          height: Targets.control,
          child: OutlinedButton.icon(
            onPressed: _busy ? null : _send,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: Text(_busy ? 'Sending…' : 'Send each household a link'),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: Space.sm),
          InfoNote(tone: NoteTone.warning, message: _error!),
        ],
      ],
    );
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(issuedStatementsProvider.notifier).issue(widget.meterId);
      if (!mounted) return;
      // A screen of its own, not more rows on this one and not a sheet.
      // Growing this list under the user left them looking at whatever the
      // old scroll offset then pointed at — a blank screen, the first time —
      // and a bottom sheet came up with zero height. A route has no such
      // ambiguity, and back navigation comes free.
      context.push(Routes.splitLinks);
    } on StatementError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,
    required this.selected,
    required this.onTap,
  });

  final SplitRule rule;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.brandSoft : c.surfaceRaised,
        borderRadius: Radii.mdAll,
        child: InkWell(
          borderRadius: Radii.mdAll,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(Space.lg),
            constraints: const BoxConstraints(minHeight: Targets.min),
            decoration: BoxDecoration(
              borderRadius: Radii.mdAll,
              border: Border.all(color: selected ? c.brand : c.outline),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(rule.label,
                          style: t.body.copyWith(color: c.textPrimary)),
                      Text(rule.description,
                          style: t.caption.copyWith(color: c.textTertiary)),
                    ],
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 20, color: c.brand),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Shares extends ConsumerWidget {
  const _Shares({required this.allocation, required this.meterId});

  final Allocation allocation;
  final String meterId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;

    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: Radii.lgAll,
        border: Border.all(color: c.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${friendlyDate(allocation.periodStart, now: allocation.periodEnd)}'
            ' to ${friendlyDate(allocation.periodEnd, now: allocation.periodEnd)}'
            ' · ${allocation.totalEnergy.format()}',
            style: t.caption.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.md),
          for (final s in allocation.shares)
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(s.occupant.name,
                        style: t.body.copyWith(color: c.textPrimary)),
                  ),
                  Text(s.amount.format(),
                      style: t.figure.copyWith(color: c.textPrimary)),
                  const SizedBox(width: Space.md),
                  IconButton(
                    tooltip: 'Send ${s.occupant.name} their receipt',
                    onPressed: () => _share(context, ref, s.occupant.id),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                  ),
                ],
              ),
            ),
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text('Meter total',
                    style: t.bodyStrong.copyWith(color: c.textSecondary)),
              ),
              Text(allocation.total.format(),
                  style: t.figure.copyWith(color: c.textSecondary)),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            allocation.sumsExactly
                ? 'The shares add up to the meter total exactly, to the kobo.'
                : 'These shares do not sum to the total.',
            style: t.caption.copyWith(
              color: allocation.sumsExactly ? c.supplyOn : c.danger,
            ),
          ),
          if (allocation.remainderGivenTo != null) ...[
            const SizedBox(height: Space.xs),
            Text(
              'A few kobo would not divide evenly and went to '
              '${allocation.remainderGivenTo}.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _share(
    BuildContext context,
    WidgetRef ref,
    String occupantId,
  ) async {
    final file = await ref.read(
      receiptFileProvider((meterId: meterId, shareId: occupantId)).future,
    );
    if (!context.mounted) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Your electricity share',
      ),
    );
  }
}

class _OccupantRow extends StatelessWidget {
  const _OccupantRow({
    required this.occupant,
    required this.rule,
    required this.onRemove,
  });

  final Occupant occupant;
  final SplitRule rule;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Dismissible(
      key: ValueKey(occupant.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.xl),
        margin: const EdgeInsets.only(bottom: Space.sm),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.18),
          borderRadius: Radii.mdAll,
        ),
        child: Icon(Icons.person_remove_outlined, color: c.danger),
      ),
      onDismissed: (_) => onRemove(),
      child: Container(
        margin: const EdgeInsets.only(bottom: Space.sm),
        padding: const EdgeInsets.all(Space.lg),
        constraints: const BoxConstraints(minHeight: Targets.min),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: Radii.mdAll,
          border: Border.all(color: c.outline),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(occupant.name,
                  style: t.body.copyWith(color: c.textPrimary)),
            ),
            Text(
              switch (rule) {
                SplitRule.byRooms =>
                  '${occupant.rooms} ${occupant.rooms == 1 ? 'room' : 'rooms'}',
                SplitRule.manual => occupant.weight.toStringAsFixed(0),
                _ => '',
              },
              style: t.caption.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}
