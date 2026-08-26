import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/entities/generator.dart';
import '../../../domain/value_objects/units.dart';
import '../application/economics_providers.dart';

Future<void> showGeneratorSheet(
  BuildContext context, {
  required String meterId,
  Generator? existing,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radii.lg),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.88,
      ),
      builder: (_) => _GeneratorSheet(meterId: meterId, existing: existing),
    );

class _GeneratorSheet extends ConsumerStatefulWidget {
  const _GeneratorSheet({required this.meterId, this.existing});

  final String meterId;
  final Generator? existing;

  @override
  ConsumerState<_GeneratorSheet> createState() => _GeneratorSheetState();
}

class _GeneratorSheetState extends ConsumerState<_GeneratorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');
  late double _kva = widget.existing?.ratedKva ?? 2.5;
  late double _lph = widget.existing?.litresPerHour ?? 1.0;
  late FuelType _fuel = widget.existing?.fuel ?? FuelType.petrol;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

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
            Text(
              widget.existing == null ? 'Your generator' : 'Edit generator',
              style: t.headline,
            ),
            const SizedBox(height: Space.lg),
            TextField(
              controller: _name,
              autofocus: widget.existing == null,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'Backup set',
              ),
            ),
            const SizedBox(height: Space.xl),
            Text('Rating: ${_kva.toStringAsFixed(1)} kVA',
                style: t.label.copyWith(color: c.textSecondary)),
            Slider(
              value: _kva,
              min: 0.5,
              max: 15,
              divisions: 29,
              onChanged: (v) => setState(() => _kva = v),
            ),
            const SizedBox(height: Space.md),
            Text('Fuel: ${_lph.toStringAsFixed(1)} litres an hour',
                style: t.label.copyWith(color: c.textSecondary)),
            Slider(
              value: _lph,
              min: 0.2,
              max: 8,
              divisions: 39,
              onChanged: (v) => setState(() => _lph = v),
            ),
            Text(
              'The most useful figure you can give Grid, and the one you can '
              'establish yourself: how long a full tank lasts. It beats any '
              'published curve, because it already contains your real load.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: Space.lg),
            SegmentedButton<FuelType>(
              segments: const [
                ButtonSegment(value: FuelType.petrol, label: Text('Petrol')),
                ButtonSegment(value: FuelType.diesel, label: Text('Diesel')),
              ],
              selected: {_fuel},
              onSelectionChanged: (s) => setState(() => _fuel = s.first),
            ),
            const SizedBox(height: Space.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _name.text.trim().isEmpty
                    ? null
                    : () {
                        ref
                            .read(generatorControllerProvider.notifier)
                            .saveSet(
                              meterId: widget.meterId,
                              name: _name.text.trim(),
                              ratedKva: _kva,
                              litresPerHour: _lph,
                              fuel: _fuel,
                              existingId: widget.existing?.id,
                            );
                        Navigator.of(context).pop();
                      },
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showFuelSheet(
  BuildContext context, {
  required String meterId,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radii.lg),
      ),
      builder: (_) => _FuelSheet(meterId: meterId),
    );

class _FuelSheet extends ConsumerStatefulWidget {
  const _FuelSheet({required this.meterId});

  final String meterId;

  @override
  ConsumerState<_FuelSheet> createState() => _FuelSheetState();
}

class _FuelSheetState extends ConsumerState<_FuelSheet> {
  final _litres = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _litres.dispose();
    _amount.dispose();
    super.dispose();
  }

  double? get _l => double.tryParse(_litres.text.trim());
  double? get _n => double.tryParse(_amount.text.replaceAll(',', '').trim());

  bool get _valid => (_l ?? 0) > 0 && (_n ?? 0) > 0;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    // The per-litre price computed live, because it is the figure that moves
    // fastest in this market and the one a user can sanity-check instantly.
    final perLitre = _valid ? Naira.fromNaira(_n! / _l!) : null;

    return Padding(
      padding: EdgeInsets.only(
        left: Space.xl,
        right: Space.xl,
        top: Space.xl,
        bottom: MediaQuery.viewInsetsOf(context).bottom + Space.xl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Fuel bought', style: t.headline),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _litres,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Litres'),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: TextField(
                  controller: _amount,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Paid',
                    prefixText: '${Naira.naira} ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            perLitre == null
                ? 'Grid records the price per litre on the day, because it is '
                    'the fastest-moving figure in the whole product.'
                : '${perLitre.format()} a litre.',
            style: t.body.copyWith(
              color: perLitre == null ? c.textTertiary : c.textSecondary,
            ),
          ),
          const SizedBox(height: Space.xl),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _valid
                  ? () {
                      ref.read(generatorControllerProvider.notifier).logFuel(
                            meterId: widget.meterId,
                            litres: _l!,
                            amount: Naira.fromNaira(_n!),
                          );
                      Navigator.of(context).pop();
                    }
                  : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
