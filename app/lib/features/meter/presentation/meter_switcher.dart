import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/entities/meter.dart';
import '../../../domain/value_objects/enums.dart';
import '../application/meter_providers.dart';

/// Switch between meters, and add another.
///
/// Feature F6. Grid assumed one meter for eight phases, and the people who
/// have several — landlords, shopkeepers, anyone reading a parent's meter
/// remotely — are disproportionately the ones who care enough to log at all.
///
/// This arrives late on purpose. Every fact was already keyed by meter, so the
/// schema does not move; what moves is the header and the router. Building it
/// in phase 1 would have meant carrying a meter switcher through eight phases
/// of churn for a feature most households never touch.
Future<void> showMeterSwitcher(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radii.lg),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.8,
    ),
    builder: (_) => const _MeterSwitcher(),
  );
}

class _MeterSwitcher extends ConsumerWidget {
  const _MeterSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final meters = ref.watch(metersProvider).value ?? const <Meter>[];
    final selected = ref.watch(selectedMeterProvider);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          Space.xl,
          Space.xl,
          Space.xl,
          Space.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your meters', style: t.headline),
            const SizedBox(height: Space.lg),
            for (final m in meters)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: _MeterRow(
                  meter: m,
                  selected: m.id == selected?.id,
                  onTap: () {
                    ref.read(selectedMeterIdProvider.notifier).select(m.id);
                    Navigator.of(context).pop();
                  },
                ),
              ),
            const SizedBox(height: Space.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  showAddMeterSheet(context);
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add another meter'),
              ),
            ),
            const SizedBox(height: Space.md),
            Text(
              'Everything in Grid — readings, the power log, packs — belongs '
              'to one meter. Switching here switches all of it, and nothing '
              'is ever averaged across them.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _MeterRow extends ConsumerWidget {
  const _MeterRow({
    required this.meter,
    required this.selected,
    required this.onTap,
  });

  final Meter meter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final t = context.type;
    final readings = ref.watch(readingsProvider(meter.id)).value ?? const [];

    return Material(
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
                    Text(meter.label,
                        style: t.body.copyWith(color: c.textPrimary)),
                    const SizedBox(height: 2),
                    Text(
                      '${meter.disco.code}'
                      '${meter.tariffBand == null ? '' : ' · Band ${meter.tariffBand!.label}'}'
                      ' · ${readings.length} '
                      '${readings.length == 1 ? 'reading' : 'readings'}',
                      style: t.caption.copyWith(color: c.textSecondary),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, size: 20, color: c.brand),
            ],
          ),
        ),
      ),
    );
  }
}

/// Adds a meter without going back through onboarding.
///
/// Onboarding exists to carry a first-time user to a forecast. A landlord
/// adding their fourth meter needs four fields and nothing else.
Future<void> showAddMeterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radii.lg),
    ),
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.88,
    ),
    builder: (_) => const _AddMeterSheet(),
  );
}

class _AddMeterSheet extends ConsumerStatefulWidget {
  const _AddMeterSheet();

  @override
  ConsumerState<_AddMeterSheet> createState() => _AddMeterSheetState();
}

class _AddMeterSheetState extends ConsumerState<_AddMeterSheet> {
  final _label = TextEditingController();
  final _number = TextEditingController();
  MeterType _type = MeterType.prepaidKeypad;
  DisCo _disco = DisCo.ikeja;
  TariffBand? _band;

  @override
  void dispose() {
    _label.dispose();
    _number.dispose();
    super.dispose();
  }

  bool get _valid => _label.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        top: Space.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Another meter', style: t.headline),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _label,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name it',
                hintText: 'The shop, or Mama’s place',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.md),
            TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Meter number',
                helperText: 'Optional, but dispute packs use it',
              ),
            ),
            const SizedBox(height: Space.lg),
            _Choice<MeterType>(
              label: 'What kind',
              value: _type,
              options: MeterType.values,
              nameOf: (m) => m.label,
              onChanged: (v) => setState(() => _type = v),
            ),
            _Choice<DisCo>(
              label: 'Distribution company',
              value: _disco,
              options: DisCo.values,
              nameOf: (d) => d.label,
              onChanged: (v) => setState(() => _disco = v),
            ),
            _Choice<TariffBand?>(
              label: 'Tariff band',
              value: _band,
              options: const [null, ...TariffBand.values],
              nameOf: (b) => b == null
                  ? 'I don’t know'
                  : 'Band ${b.label} — ${b.committedHours} hours a day',
              onChanged: (v) => setState(() => _band = v),
            ),
            const SizedBox(height: Space.lg),
            Text(
              'Grid keeps each meter’s record completely separate.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: Space.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _valid ? _save : null,
                child: const Text('Add it'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final id = ref.read(uuidProvider).v7();
    await ref.read(meterRepositoryProvider).save(
          Meter(
            id: id,
            label: _label.text.trim(),
            type: _type,
            disco: _disco,
            createdAt: ref.read(clockProvider)(),
            meterNumber:
                _number.text.trim().isEmpty ? null : _number.text.trim(),
            tariffBand: _band,
          ),
        );
    // Switch to it: somebody who has just added a meter is about to read it.
    ref.read(selectedMeterIdProvider.notifier).select(id);
    if (mounted) Navigator.of(context).pop();
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
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
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: t.caption.copyWith(color: c.textSecondary)),
          const SizedBox(height: Space.xs),
          InkWell(
            onTap: () => _pick(context),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: Targets.min),
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: Radii.mdAll,
                border: Border.all(color: c.outline),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(nameOf(value),
                        style: t.body.copyWith(color: c.textPrimary)),
                  ),
                  Icon(Icons.expand_more_rounded,
                      size: 18, color: c.textTertiary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(BuildContext context) async {
    final chosen = await showModalBottomSheet<_Wrapped<T>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radii.lg),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(Space.lg),
          children: [
            for (final o in options)
              ListTile(
                title: Text(nameOf(o)),
                trailing: o == value
                    ? Icon(Icons.check_rounded, color: sheet.colors.brand)
                    : null,
                // Wrapped so a null option survives the pop. "I don't know" is
                // a real answer for a tariff band, and an unwrapped null would
                // be indistinguishable from the sheet being dismissed —
                // silently keeping whatever was selected before.
                onTap: () => Navigator.of(sheet).pop(_Wrapped<T>(o)),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) onChanged(chosen.value);
  }
}

/// Lets a nullable choice survive a `pop`.
class _Wrapped<T> {
  const _Wrapped(this.value);
  final T value;
}
