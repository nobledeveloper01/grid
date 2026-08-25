import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';

/// A large custom keypad.
///
/// Deliberately not the system keyboard: this is used outdoors at a meter,
/// one-handed, sometimes in the rain. Keys are `outdoor` sized.
class NumericKeypad extends StatelessWidget {
  const NumericKeypad({
    super.key,
    required this.onDigit,
    required this.onDecimal,
    required this.onBackspace,
  });

  final void Function(String digit) onDigit;
  final VoidCallback onDecimal;
  final VoidCallback onBackspace;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: Row(
              children: [
                for (final key in row) ...[
                  Expanded(child: _Key(label: key, onTap: () => onDigit(key))),
                  if (key != row.last) const SizedBox(width: Space.sm),
                ],
              ],
            ),
          ),
        Row(
          children: [
            Expanded(child: _Key(label: '.', onTap: onDecimal)),
            const SizedBox(width: Space.sm),
            Expanded(child: _Key(label: '0', onTap: () => onDigit('0'))),
            const SizedBox(width: Space.sm),
            Expanded(
              child: _Key(
                icon: Icons.backspace_outlined,
                semanticLabel: 'Delete',
                onTap: onBackspace,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({
    this.label,
    this.icon,
    this.semanticLabel,
    required this.onTap,
  });

  final String? label;
  final IconData? icon;
  final String? semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Semantics(
      button: true,
      label: semanticLabel ?? label,
      child: Material(
        color: c.surfaceDim,
        borderRadius: Radii.mdAll,
        child: InkWell(
          borderRadius: Radii.mdAll,
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: SizedBox(
            height: Targets.outdoor,
            child: Center(
              child: icon != null
                  ? Icon(icon, color: c.textPrimary)
                  : Text(
                      label!,
                      style: t.figure.copyWith(fontSize: 24),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
