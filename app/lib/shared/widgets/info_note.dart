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
            // Buttons in this app are sized to fill their parent, so a Wrap
            // gave every action its own full-width row and turned a note
            // into a stack of banners. Sharing one row keeps the note a
            // note; a single action still spans it, which is correct.
            Row(
              children: [
                for (final (i, action) in actions!.indexed) ...[
                  Expanded(child: action),
                  if (i != actions!.length - 1)
                    const SizedBox(width: Space.sm),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
