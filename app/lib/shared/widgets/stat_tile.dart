import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// A small metric card.
///
/// [tone] tints the icon and its backing chip only — never the value, which
/// stays `textPrimary` so a row of tiles reads as one set of figures rather
/// than as a paint chart.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.tone,
    this.caption,
    this.isEstimate = false,
    this.isNumeric = true,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? tone;
  final String? caption;

  /// Modelled rather than measured. Renders the value in `estimate` with a
  /// dashed underline, because mistaking an estimate for a measurement is
  /// the failure mode this product most needs to prevent.
  final bool isEstimate;

  /// Numeric values use the tabular monospace face so a column of them
  /// aligns. Words do not — monospace makes "Band A" read as a wide,
  /// broken-looking string rather than as a label.
  final bool isNumeric;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;
    final accent = tone ?? c.brandDeep;

    return Semantics(
      button: onTap != null,
      label: '$label: $value${isEstimate ? ', estimated' : ''}',
      child: Material(
        color: c.surfaceRaised,
        borderRadius: Radii.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: Radii.mdAll,
          child: Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              borderRadius: Radii.mdAll,
              border: Border.all(color: c.outline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(Space.sm),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: Radii.smAll,
                  ),
                  child: Icon(icon, size: 18, color: accent),
                ),
                const SizedBox(height: Space.md),
                Builder(
                  builder: (context) {
                    final base = isNumeric ? t.figure : t.title;
                    return Text(
                      value,
                      style: isEstimate
                          ? base.copyWith(
                              color: c.estimate,
                              decoration: TextDecoration.underline,
                              decorationStyle: TextDecorationStyle.dashed,
                              decorationColor: c.estimate,
                            )
                          : base.copyWith(color: c.textPrimary),
                    );
                  },
                ),
                const SizedBox(height: Space.xs),
                Text(
                  label,
                  style: t.caption.copyWith(color: c.textSecondary),
                ),
                if (caption != null) ...[
                  const SizedBox(height: Space.xs),
                  Text(
                    caption!,
                    style: t.caption.copyWith(
                      color: c.textTertiary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
