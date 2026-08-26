import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// A numeric figure with its unit.
///
/// The number is set in the tabular monospace face so a column of them
/// aligns; the unit is set in the sans face, because monospace puts "kWh" on
/// three tabular advance widths and opens a gap that reads as a typo.
class Figure extends StatelessWidget {
  const Figure({
    super.key,
    required this.value,
    required this.unit,
    this.style,
    this.colour,
    this.isEstimate = false,
  });

  final String value;
  final String unit;

  /// Defaults to the `figure` style. Pass `meter` for a reading.
  final TextStyle? style;

  final Color? colour;

  /// Modelled rather than measured — rendered in `estimate` with a dashed
  /// underline, because mistaking an estimate for a measurement is the
  /// failure mode this product most needs to prevent.
  final bool isEstimate;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final base = (style ?? t.figure);
    final fg = colour ?? (isEstimate ? c.estimate : c.textPrimary);

    return Semantics(
      label: '$value $unit${isEstimate ? ', estimated' : ''}',
      child: ExcludeSemantics(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: base.copyWith(
                color: fg,
                decoration: isEstimate ? TextDecoration.underline : null,
                decorationStyle: TextDecorationStyle.dashed,
                decorationColor: isEstimate ? c.estimate : null,
              ),
            ),
            const SizedBox(width: Space.xs),
            Text(
              unit,
              style: t.caption.copyWith(
                color: c.textSecondary,
                fontSize: (base.fontSize ?? 17) * 0.62,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
