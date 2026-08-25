import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';
import '../application/reading_controller.dart';

/// Records a prepaid unit purchase.
///
/// If only the amount is entered, units are derived at the configured rate
/// and marked as derived. If both are entered, the effective rate is
/// computed — and a sustained divergence from the band rate is direct
/// evidence of misclassification.
class PurchaseEntryScreen extends ConsumerStatefulWidget {
  const PurchaseEntryScreen({super.key});

  @override
  ConsumerState<PurchaseEntryScreen> createState() =>
      _PurchaseEntryScreenState();
}

class _PurchaseEntryScreenState extends ConsumerState<PurchaseEntryScreen> {
  final _amount = TextEditingController();
  final _units = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _units.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final meter = ref.watch(selectedMeterProvider);
    final t = context.type;
    final c = context.colors;

    if (meter == null) {
      return const GridScaffold(title: 'Bought units', body: SizedBox.shrink());
    }

    final rate = ref.watch(effectiveRateProvider(meter.id));
    final amount = double.tryParse(_amount.text);
    final units = double.tryParse(_units.text);

    final derivedUnits = (amount != null && units == null && rate != null)
        ? rate.energyFor(Naira.fromNaira(amount))
        : null;

    final effectiveRate = (amount != null && units != null && units > 0)
        ? Rate.fromKobo(
            (Naira.fromNaira(amount).kobo * 1000 /
                    Kwh.fromDouble(units).milli)
                .round(),
          )
        : null;

    final divergent = effectiveRate != null &&
        rate != null &&
        (effectiveRate.koboPerKwh - rate.koboPerKwh).abs() >
            rate.koboPerKwh * 0.10;

    return GridScaffold(
      title: 'Bought units',
      body: ListView(
        children: [
          const SizedBox(height: Space.lg),
          Text('How much did you pay?', style: t.bodyStrong),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(prefixText: '₦ '),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.xl),
          Text('How many units did you get?', style: t.bodyStrong),
          const SizedBox(height: Space.xs),
          Text(
            "On your receipt or token slip. Leave it blank if you don't have it.",
            style: t.caption.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: _units,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(suffixText: 'kWh'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.xl),
          if (derivedUnits != null)
            InfoNote(
              tone: NoteTone.estimate,
              message: "That's about ${derivedUnits.format()} at "
                  '${rate!.format()}. Grid will mark this as an estimate — '
                  'add the units from your receipt to make it exact.',
            ),
          if (effectiveRate != null && !divergent)
            InfoNote(
              message: 'You paid ${effectiveRate.format()}.',
            ),
          if (divergent)
            InfoNote(
              tone: NoteTone.warning,
              message: 'You paid ${effectiveRate.format()}, but Band '
                  '${meter.tariffBand?.label ?? '?'} should be '
                  '${rate.format()}. Worth watching — if this keeps '
                  'happening, it is evidence your band is wrong.',
            ),
          const SizedBox(height: Space.xxl),
        ],
      ),
      bottom: FilledButton(
        onPressed: (amount == null || _saving)
            ? null
            : () => _save(meter.id, amount, units),
        child: const Text('Save'),
      ),
    );
  }

  Future<void> _save(String meterId, double amount, double? units) async {
    setState(() => _saving = true);
    await ref.read(readingControllerProvider.notifier).addPurchase(
          meterId: meterId,
          amount: Naira.fromNaira(amount),
          units: units == null ? null : Kwh.fromDouble(units),
        );
    if (!mounted) return;
    context.pop();
  }
}
