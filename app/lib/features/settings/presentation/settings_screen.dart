import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/providers.dart';
import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/entities/meter.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';

/// Everything about the meter that onboarding asked once and never again.
///
/// Bands get reclassified, tariffs change, and people move house. A product
/// whose central claim rests on the band the user is billed at cannot make
/// that value un-editable after the first screen.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    if (meter == null) {
      return const GridScaffold(title: 'Settings', body: SizedBox.shrink());
    }

    final c = context.colors;
    final t = context.type;
    final rate = ref.watch(effectiveRateProvider(meter.id));

    void save(Meter updated) =>
        ref.read(meterRepositoryProvider).save(updated);

    return GridScaffold(
      title: 'Settings',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          _Group(
            title: 'This meter',
            children: [
              _TextRow(
                label: 'Name',
                value: meter.label,
                hint: 'Home',
                onSaved: (v) => save(meter.copyWith(label: v)),
              ),
              _TextRow(
                label: 'Meter number',
                value: meter.meterNumber,
                hint: 'Printed on the meter',
                keyboard: TextInputType.number,
                onSaved: (v) => save(meter.copyWith(meterNumber: v)),
              ),
              _TextRow(
                label: 'Address',
                value: meter.address,
                hint: 'Used on dispute packs',
                onSaved: (v) => save(meter.copyWith(address: v)),
              ),
              _TextRow(
                label: 'LGA',
                value: meter.lga,
                hint: 'Local government area',
                onSaved: (v) => save(meter.copyWith(lga: v)),
              ),
            ],
          ),

          const SizedBox(height: Space.lg),
          _Group(
            title: 'Tariff',
            children: [
              _PickerRow<DisCo>(
                label: 'Distribution company',
                value: meter.disco,
                options: DisCo.values,
                nameOf: (d) => d.label,
                onChanged: (d) => save(meter.copyWith(disco: d)),
              ),
              _PickerRow<TariffBand?>(
                label: 'Tariff band',
                value: meter.tariffBand,
                options: [null, ...TariffBand.values],
                nameOf: (b) => b == null
                    ? 'Not set'
                    : 'Band ${b.label} — ${b.committedHours} hours a day',
                onChanged: (b) => save(
                  Meter(
                    id: meter.id,
                    label: meter.label,
                    type: meter.type,
                    disco: meter.disco,
                    createdAt: meter.createdAt,
                    meterNumber: meter.meterNumber,
                    // copyWith cannot clear a nullable field, and clearing
                    // the band has to be possible: a user who does not know
                    // theirs is better served by an empty value than by a
                    // guess the compliance engine will treat as a promise.
                    tariffBand: b,
                    rateOverride: meter.rateOverride,
                    digitCount: meter.digitCount,
                    address: meter.address,
                    lga: meter.lga,
                    parentMeterId: meter.parentMeterId,
                    unitId: meter.unitId,
                    supplyDetectionEnabled: meter.supplyDetectionEnabled,
                    isArchived: meter.isArchived,
                  ),
                ),
              ),
              _TextRow(
                label: 'Rate override',
                value: meter.rateOverride?.value.toStringAsFixed(2),
                hint: rate == null
                    ? 'Naira per kWh'
                    : 'Currently ${rate.format()}',
                keyboard: TextInputType.number,
                onSaved: (v) {
                  final parsed = double.tryParse(v ?? '');
                  save(meter.copyWith(
                    rateOverride:
                        parsed == null ? null : Rate.fromNaira(parsed),
                  ));
                },
              ),
            ],
          ),

          const SizedBox(height: Space.lg),
          _Group(
            title: 'Power logging',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: meter.supplyDetectionEnabled,
                onChanged: (v) =>
                    save(meter.copyWith(supplyDetectionEnabled: v)),
                title: Text(
                  'Guess from charging',
                  style: t.body.copyWith(color: c.textPrimary),
                ),
                subtitle: Text(
                  'Grid watches when your phone starts and stops charging to '
                  'work out when the power was on. Turn this off if you run '
                  'an inverter — charging no longer follows the mains, and '
                  'the log would be fiction that looks like measurement.',
                  style: t.caption.copyWith(color: c.textTertiary),
                ),
              ),
            ],
          ),

          const SizedBox(height: Space.lg),
          _Group(
            title: 'Your record',
            children: [
              _LinkRow(
                label: 'Readings',
                onTap: () => context.push(Routes.readingHistory),
              ),
              _LinkRow(
                label: 'Power log',
                onTap: () => context.push(Routes.supplyTimeline),
              ),
              _LinkRow(
                label: 'Appliances',
                onTap: () => context.push(Routes.appliances),
              ),
              _LinkRow(
                label: 'Dispute packs',
                onTap: () => context.push(Routes.dispute),
              ),
              _LinkRow(
                label: 'Cases',
                onTap: () => context.push(Routes.cases),
              ),
            ],
          ),

          const SizedBox(height: Space.lg),
          const InfoNote(
            icon: Icons.lock_outline_rounded,
            message: 'Everything Grid holds is on this phone. There is no '
                'account and no server — nothing leaves the device unless '
                'you share a pack yourself.',
          ),

          const SizedBox(height: Space.lg),
          Text(
            'Grid · a record you keep, not one you are given.',
            textAlign: TextAlign.center,
            style: t.caption.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Space.xxxl),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
          child: Text(
            title.toUpperCase(),
            style: t.label.copyWith(color: c.textSecondary, letterSpacing: 0.8),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg),
          decoration: BoxDecoration(
            color: c.surfaceRaised,
            borderRadius: Radii.mdAll,
            border: Border.all(color: c.outline),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }
}

/// A value that opens a sheet to edit it. Editing in place inside a list is
/// how a settings screen ends up with a keyboard covering the field being
/// typed into.
class _TextRow extends StatelessWidget {
  const _TextRow({
    required this.label,
    required this.value,
    required this.hint,
    required this.onSaved,
    this.keyboard,
  });

  final String label;
  final String? value;
  final String hint;
  final TextInputType? keyboard;
  final ValueChanged<String?> onSaved;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return InkWell(
      onTap: () => _edit(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: Targets.min),
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: t.body.copyWith(color: c.textPrimary)),
            ),
            const SizedBox(width: Space.md),
            Flexible(
              child: Text(
                value?.isNotEmpty == true ? value! : 'Not set',
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: t.body.copyWith(
                  color: value?.isNotEmpty == true
                      ? c.textSecondary
                      : c.textTertiary,
                ),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context) async {
    final controller = TextEditingController(text: value ?? '');
    final result = await showModalBottomSheet<String?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radii.lg),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          left: Space.xl,
          right: Space.xl,
          top: Space.xl,
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + Space.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: sheetContext.type.headline),
            const SizedBox(height: Space.lg),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: keyboard,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(hintText: hint),
              onSubmitted: (v) => Navigator.of(sheetContext).pop(v),
            ),
            const SizedBox(height: Space.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(controller.text),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (result != null) onSaved(result.trim().isEmpty ? null : result.trim());
  }
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.value,
    required this.options,
    required this.nameOf,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T) nameOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return InkWell(
      onTap: () => _pick(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: Targets.min),
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: t.body.copyWith(color: c.textPrimary)),
            ),
            const SizedBox(width: Space.md),
            Flexible(
              child: Text(
                nameOf(value),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: t.body.copyWith(color: c.textSecondary),
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final chosen = await showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radii.lg),
      ),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(Space.lg),
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: Space.md),
              child: Text(label, style: sheetContext.type.headline),
            ),
            for (final option in options)
              ListTile(
                title: Text(nameOf(option)),
                trailing: option == value
                    ? Icon(Icons.check_rounded,
                        color: sheetContext.colors.brand)
                    : null,
                onTap: () => Navigator.of(sheetContext).pop(option),
              ),
          ],
        ),
      ),
    );
    // A sheet dismissed by swiping down returns null, which for a nullable
    // option type is indistinguishable from choosing "Not set" — so the
    // sentinel has to be the absence of a pop value, not the value itself.
    if (chosen != null || options.contains(null)) {
      if (chosen != null) onChanged(chosen);
    }
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: Targets.min),
        padding: const EdgeInsets.symmetric(vertical: Space.md),
        child: Row(
          children: [
            Expanded(
              child: Text(label, style: t.body.copyWith(color: c.textPrimary)),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: c.textTertiary),
          ],
        ),
      ),
    );
  }
}
