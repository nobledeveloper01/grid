import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// A large, illustrated choice. Used wherever the user picks one option from
/// a small set — meter type, DisCo, tariff band.
///
/// Targets are `outdoor` sized, because the same component appears in flows
/// the user may be running while standing at a meter.
class SelectableCard extends StatelessWidget {
  const SelectableCard({
    super.key,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.icon,
    this.selected = false,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: Radii.mdAll,
        child: Container(
          constraints: const BoxConstraints(minHeight: Targets.control),
          padding: const EdgeInsets.all(Space.lg),
          decoration: BoxDecoration(
            // surfaceRaised, not surfaceDim: on the dark theme surfaceDim sits
            // almost exactly on the page colour, and a list of them reads as
            // flat text rather than as a set of choices.
            color: selected ? c.brandSoft : c.surfaceRaised,
            borderRadius: Radii.mdAll,
            border: Border.all(
              color: selected ? c.brand : c.outline,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 24,
                  color: selected ? c.brandDeep : c.textSecondary,
                ),
                const SizedBox(width: Space.lg),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: t.bodyStrong),
                    if (subtitle != null) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        subtitle!,
                        style: t.caption.copyWith(color: c.textSecondary),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
              // Selection carries an icon as well as colour — colour is
              // never the sole carrier of meaning.
              // Selection carries an icon as well as colour — colour is
              // never the sole carrier of meaning.
              if (selected && trailing == null)
                Icon(Icons.check_circle_rounded, color: c.brandDeep),
            ],
          ),
        ),
      ),
    );
  }
}
