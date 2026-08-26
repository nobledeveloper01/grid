import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/services/budget_engine.dart';
import '../../../domain/value_objects/units.dart';
import '../application/budget_providers.dart';

/// Set a monthly budget and the day money arrives.
///
/// Two fields, because the second one is the whole point: a depletion date
/// only becomes a decision when there is another date to measure it against.
Future<void> showBudgetSheet(
  BuildContext context, {
  required String meterId,
  Budget? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radii.lg),
    ),
    builder: (_) => _BudgetSheet(meterId: meterId, existing: existing),
  );
}

class _BudgetSheet extends ConsumerStatefulWidget {
  const _BudgetSheet({required this.meterId, this.existing});

  final String meterId;
  final Budget? existing;

  @override
  ConsumerState<_BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<_BudgetSheet> {
  late final TextEditingController _amount;
  late int _payDay;

  @override
  void initState() {
    super.initState();
    _amount = TextEditingController(
      text: widget.existing == null
          ? ''
          : widget.existing!.monthly.value.round().toString(),
    );
    _payDay = widget.existing?.payDayOfMonth ?? 28;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _parsed =>
      double.tryParse(_amount.text.replaceAll(',', '').trim());

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
            Text('Your budget', style: t.headline),
            const SizedBox(height: Space.sm),
            Text(
              'Grid already knows when your units run out. Tell it when money '
              'comes in and it can tell you whether one reaches the other.',
              style: t.body.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: Space.xl),

            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              autofocus: widget.existing == null,
              decoration: InputDecoration(
                labelText: 'Monthly budget',
                prefixText: '${Naira.naira} ',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Space.xl),

            Text(
              'Money comes in on the ${_ordinal(_payDay)}',
              style: t.label.copyWith(color: c.textSecondary),
            ),
            const SizedBox(height: Space.sm),
            Slider(
              value: _payDay.toDouble(),
              min: 1,
              max: 31,
              divisions: 30,
              label: _ordinal(_payDay),
              onChanged: (v) => setState(() => _payDay = v.round()),
            ),
            Text(
              'Grid clamps this to the last day of a short month, so the '
              '31st still lands in February.',
              style: t.caption.copyWith(color: c.textTertiary),
            ),
            const SizedBox(height: Space.xl),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_parsed ?? 0) > 0
                    ? () {
                        ref.read(budgetControllerProvider.notifier).set(
                              meterId: widget.meterId,
                              monthly: Naira.fromNaira(_parsed!),
                              payDayOfMonth: _payDay,
                            );
                        Navigator.of(context).pop();
                      }
                    : null,
                child: const Text('Save'),
              ),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: Space.sm),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    ref
                        .read(budgetControllerProvider.notifier)
                        .clear(widget.meterId);
                    Navigator.of(context).pop();
                  },
                  child: const Text('Remove the budget'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _ordinal(int day) {
    if (day >= 11 && day <= 13) return '${day}th';
    return switch (day % 10) {
      1 => '${day}st',
      2 => '${day}nd',
      3 => '${day}rd',
      _ => '${day}th',
    };
  }
}
