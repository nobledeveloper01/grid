import 'package:flutter/material.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';

/// A section title with an optional trailing action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final t = context.type;

    // No coloured left bar. `border-left: 3px solid <accent>` is one of the
    // most recognisable template idioms going, and it is doing work that
    // type should do: a section is distinguished by weight and spacing, not
    // by a decorative rule.
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: t.title.copyWith(letterSpacing: -0.2),
          ),
        ),
        if (action != null && onAction != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!),
                const SizedBox(width: Space.xs),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
      ],
    );
  }
}
