import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/entities/appliance.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../insights/application/insights_providers.dart';
import '../../meter/application/meter_providers.dart';

/// What the household runs.
///
/// Data entry the user does for their own benefit, so it has to pay back
/// immediately: the sheet shows what an appliance costs a month the moment
/// its hours are set, before anything is saved.
class ApplianceScreen extends ConsumerWidget {
  const ApplianceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    final c = context.colors;
    final t = context.type;

    if (meter == null) {
      return const GridScaffold(title: 'Appliances', body: SizedBox.shrink());
    }

    final appliances =
        ref.watch(appliancesProvider(meter.id)).value ?? const <Appliance>[];

    return GridScaffold(
      title: 'Appliances',
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        children: [
          const InfoNote(
            message: 'Grid uses this to work out where your units go. The '
                'wattages are typical figures, not measurements — change any '
                'of them if you know better.',
          ),
          const SizedBox(height: Space.lg),
          if (appliances.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xxl),
              child: Text(
                'Nothing added yet.',
                textAlign: TextAlign.center,
                style: t.body.copyWith(color: c.textTertiary),
              ),
            )
          else
            for (final a in appliances)
              _ApplianceTile(
                appliance: a,
                onEdit: () => _openSheet(context, ref, meter.id, existing: a),
                onRemove: () => ref
                    .read(applianceRepositoryProvider)
                    .remove(a.id),
              ),
          const SizedBox(height: Space.xxxl),
        ],
      ),
      bottom: FilledButton.icon(
        onPressed: () => _openSheet(context, ref, meter.id),
        icon: const Icon(Icons.add),
        label: const Text('Add an appliance'),
      ),
    );
  }

  void _openSheet(
    BuildContext context,
    WidgetRef ref,
    String meterId, {
    Appliance? existing,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radii.lg),
      ),
      // Capped short of the top of the screen. A scroll-controlled sheet with
      // this much in it grows to full height and puts its own title under the
      // Dynamic Island; the top inset does not reach inside the sheet's
      // MediaQuery, so the height is what has to give.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      builder: (_) => _ApplianceSheet(meterId: meterId, existing: existing),
    );
  }
}

class _ApplianceTile extends StatelessWidget {
  const _ApplianceTile({
    required this.appliance,
    required this.onEdit,
    required this.onRemove,
  });

  final Appliance appliance;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Dismissible(
      key: ValueKey(appliance.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.xl),
        margin: const EdgeInsets.only(bottom: Space.sm),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.18),
          borderRadius: Radii.mdAll,
        ),
        child: Icon(Icons.delete_outline, color: c.danger),
      ),
      // An appliance is *state*, not a fact — it describes the household as
      // it is now, so removing one is an ordinary edit rather than a deletion
      // of evidence. Readings and supply events have no such path.
      onDismissed: (_) => onRemove(),
      child: Padding(
        padding: const EdgeInsets.only(bottom: Space.sm),
        child: Material(
          color: c.surfaceRaised,
          borderRadius: Radii.mdAll,
          child: InkWell(
            onTap: onEdit,
            borderRadius: Radii.mdAll,
            child: Container(
              constraints: const BoxConstraints(minHeight: Targets.min),
              padding: const EdgeInsets.all(Space.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          appliance.quantity > 1
                              ? '${appliance.name} ×${appliance.quantity}'
                              : appliance.name,
                          style: t.body.copyWith(color: c.textPrimary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${appliance.ratedWatts} W · '
                          '${runtimeLabel(appliance.hoursPerDay)}',
                          style: t.caption.copyWith(color: c.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    appliance.modelledDailyKwh.format(),
                    style: t.caption.copyWith(color: c.estimate),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}

/// How long something runs, as a phrase rather than a number plus a suffix.
///
/// Composing '${hours(h)} a day' produced "all day a day", and sub-hour
/// figures read better in minutes: nobody runs an iron for "0.4 hours".
String runtimeLabel(double hours) {
  if (hours <= 0) return 'never';
  if (hours >= 24) return 'all day';
  if (hours < 1) return '${(hours * 60).round()} minutes a day';
  if (hours == hours.roundToDouble()) {
    return '${hours.round()} ${hours == 1 ? 'hour' : 'hours'} a day';
  }
  return '${hours.toStringAsFixed(1)} hours a day';
}

class _ApplianceSheet extends ConsumerStatefulWidget {
  const _ApplianceSheet({required this.meterId, this.existing});

  final String meterId;
  final Appliance? existing;

  @override
  ConsumerState<_ApplianceSheet> createState() => _ApplianceSheetState();
}

class _ApplianceSheetState extends ConsumerState<_ApplianceSheet> {
  late final TextEditingController _name;
  late final TextEditingController _watts;
  late double _hours;
  late int _quantity;
  late bool _mainsOnly;
  String? _catalogueKey;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _watts = TextEditingController(text: e?.ratedWatts.toString() ?? '');
    _hours = e?.hoursPerDay ?? 4;
    _quantity = e?.quantity ?? 1;
    _mainsOnly = e?.mainsOnly ?? true;
    _catalogueKey = e?.catalogueKey;
  }

  @override
  void dispose() {
    _name.dispose();
    _watts.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty && (int.tryParse(_watts.text) ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final catalogue = ref.watch(applianceCatalogueProvider).value;
    final rate = ref.watch(effectiveRateProvider(widget.meterId));

    final watts = int.tryParse(_watts.text) ?? 0;
    final dailyKwh = watts * _quantity * _hours / 1000;
    final monthly = rate?.costOf(Kwh.fromDouble(dailyKwh * 30));

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
            Text(
              widget.existing == null ? 'Add an appliance' : 'Edit appliance',
              style: t.headline.copyWith(color: c.textPrimary),
            ),
            const SizedBox(height: Space.lg),

            if (catalogue != null && widget.existing == null) ...[
              Text(
                'Start from a common one',
                style: t.label.copyWith(color: c.textSecondary),
              ),
              const SizedBox(height: Space.sm),
              Wrap(
                spacing: Space.sm,
                runSpacing: Space.sm,
                children: [
                  for (final e in catalogue.entries.take(14))
                    ActionChip(
                      label: Text(e.name),
                      onPressed: () => setState(() {
                        _name.text = e.name;
                        _watts.text = e.watts.toString();
                        _hours = e.hours;
                        _mainsOnly = e.mainsOnly;
                        _catalogueKey = e.key;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: Space.lg),
            ],

            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Name'),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.md),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _watts,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Watts',
                      helperText: 'Printed on the plate',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: _Stepper(
                    label: 'How many',
                    value: _quantity,
                    onChanged: (v) => setState(() => _quantity = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.lg),

            Text(
              'Runs ${runtimeLabel(_hours)}',
              style: t.label.copyWith(color: c.textSecondary),
            ),
            Slider(
              value: _hours,
              min: 0,
              max: 24,
              divisions: 48,
              label: runtimeLabel(_hours),
              onChanged: (v) => setState(() => _hours = v),
            ),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _mainsOnly,
              onChanged: (v) => setState(() => _mainsOnly = v),
              title: Text(
                'Only runs on mains',
                style: t.body.copyWith(color: c.textPrimary),
              ),
              subtitle: Text(
                'Off if it also runs on your inverter or generator. Grid caps '
                'mains-only hours at the hours power was actually there.',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
            ),
            const SizedBox(height: Space.lg),

            // The payback for filling this in, shown before anything is
            // saved. An inventory screen that only pays off two screens away
            // is an inventory screen nobody completes.
            if (watts > 0)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(Space.lg),
                decoration: BoxDecoration(
                  color: c.estimateSoft,
                  borderRadius: Radii.mdAll,
                ),
                child: Text.rich(
                  TextSpan(
                    style: t.body.copyWith(color: c.textSecondary),
                    children: [
                      const TextSpan(text: 'About '),
                      TextSpan(
                        text: Kwh.fromDouble(dailyKwh).format(),
                        style: t.bodyStrong.copyWith(color: c.estimate),
                      ),
                      const TextSpan(text: ' a day'),
                      if (monthly != null) ...[
                        const TextSpan(text: ', roughly '),
                        TextSpan(
                          text: monthly.format(),
                          style: t.bodyStrong.copyWith(color: c.estimate),
                        ),
                        const TextSpan(text: ' a month at your rate'),
                      ],
                      const TextSpan(text: '. An estimate, not a measurement.'),
                    ],
                  ),
                  textScaler: MediaQuery.textScalerOf(context),
                ),
              ),
            const SizedBox(height: Space.lg),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _valid ? _save : null,
                child: Text(widget.existing == null ? 'Add' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _save() {
    final repo = ref.read(applianceRepositoryProvider);
    repo.save(Appliance(
      id: widget.existing?.id ?? ref.read(uuidProvider).v7(),
      meterId: widget.meterId,
      name: _name.text.trim(),
      ratedWatts: int.parse(_watts.text),
      quantity: _quantity,
      hoursPerDay: _hours,
      mainsOnly: _mainsOnly,
      catalogueKey: _catalogueKey,
    ));
    Navigator.of(context).pop();
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: t.caption.copyWith(color: c.textSecondary)),
        const SizedBox(height: Space.xs),
        Row(
          children: [
            // Styled here rather than through `iconButtonTheme`. Material 3
            // routes every IconButton variant through that one theme, so
            // setting a background on it put an amber disc behind the app
            // bar's back chevron as well.
            _StepButton(
              icon: Icons.remove,
              onPressed: value > 1 ? () => onChanged(value - 1) : null,
            ),
            Expanded(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: t.figure.copyWith(color: c.textPrimary),
              ),
            ),
            _StepButton(
              icon: Icons.add,
              onPressed: value < 20 ? () => onChanged(value + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});

  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    return Material(
      color: enabled ? c.brandSoft : c.surfaceDim,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: Targets.min,
          height: Targets.min,
          child: Icon(
            icon,
            size: 20,
            color: enabled ? c.brand : c.textTertiary,
          ),
        ),
      ),
    );
  }
}
