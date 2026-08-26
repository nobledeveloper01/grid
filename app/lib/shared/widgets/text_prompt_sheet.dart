import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// Asks for one line of text in a bottom sheet, and returns it.
///
/// This exists because the obvious way to do it crashes. Creating a
/// `TextEditingController` at the call site, awaiting `showModalBottomSheet`
/// and then disposing the controller looks correct and is not: the sheet's
/// route is still animating out when the await returns, its `TextField` is
/// still mounted, and disposing the controller out from under it throws
/// `_dependents.isEmpty: is not true` — an assertion whose message says
/// nothing at all about text controllers.
///
/// The fix is ownership. The sheet's own widget creates the controller and
/// disposes it in its own `dispose`, which runs when the route has actually
/// gone. Returns null when dismissed.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  String? description,
  String? initialValue,
  String? hintText,
  String confirmLabel = 'Save',
  TextInputType? keyboardType,
  int maxLines = 1,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radii.lg),
    ),
    builder: (_) => _TextPromptSheet(
      title: title,
      description: description,
      initialValue: initialValue,
      hintText: hintText,
      confirmLabel: confirmLabel,
      keyboardType: keyboardType,
      maxLines: maxLines,
    ),
  );
}

class _TextPromptSheet extends StatefulWidget {
  const _TextPromptSheet({
    required this.title,
    required this.description,
    required this.initialValue,
    required this.hintText,
    required this.confirmLabel,
    required this.keyboardType,
    required this.maxLines,
  });

  final String title;
  final String? description;
  final String? initialValue;
  final String? hintText;
  final String confirmLabel;
  final TextInputType? keyboardType;
  final int maxLines;

  @override
  State<_TextPromptSheet> createState() => _TextPromptSheetState();
}

class _TextPromptSheetState extends State<_TextPromptSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialValue ?? '');

  @override
  void dispose() {
    _controller.dispose();
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.title, style: t.headline),
          if (widget.description != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              widget.description!,
              style: t.caption.copyWith(color: c.textTertiary),
            ),
          ],
          const SizedBox(height: Space.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: widget.keyboardType,
            maxLines: widget.maxLines,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(hintText: widget.hintText),
            onSubmitted: widget.maxLines == 1
                ? (v) => Navigator.of(context).pop(v)
                : null,
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(_controller.text),
              child: Text(widget.confirmLabel),
            ),
          ),
        ],
      ),
    );
  }
}
