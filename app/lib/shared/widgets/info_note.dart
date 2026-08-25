import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

enum NoteTone { neutral, estimate, warning, danger }

/// An inline explanatory note.
///
/// Used for coverage statements, estimate labels and validation warnings.
/// Never a modal: a warning is information, not an obstacle.
class InfoNote extends StatelessWidget {
  const InfoNote({
    super.key,
    required this.message,
    this.tone = NoteTone.neutral,
    this.icon,
    this.actions,
  });

  final String message;
  final NoteTone tone;
  final IconData? icon;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    final (fg, bg) = switch (tone) {
      NoteTone.neutral => (c.textSecondary, c.surfaceDim),
      NoteTone.estimate => (c.estimate, c.surfaceDim),
      NoteTone.warning => (c.warning, c.surfaceDim),
      NoteTone.danger => (c.danger, c.surfaceDim),
    };

    final defaultIcon = switch (tone) {
      NoteTone.neutral => Icons.info_outline,
      NoteTone.estimate => Icons.show_chart,
      NoteTone.warning => Icons.error_outline,
      NoteTone.danger => Icons.warning_amber_rounded,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: Radii.mdAll,
        border: Border.all(color: fg.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon ?? defaultIcon, size: 20, color: fg),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text(
                  message,
                  style: t.body.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: Space.md),
            Wrap(spacing: Space.sm, runSpacing: Space.sm, children: actions!),
          ],
        ],
      ),
    );
  }
}
