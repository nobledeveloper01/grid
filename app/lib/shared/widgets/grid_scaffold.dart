import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/theme/tokens.dart';

/// Standard page chrome. Screen padding is `lg` on compact and `xl` from
/// medium up, per the layout spec.
class GridScaffold extends StatelessWidget {
  const GridScaffold({
    super.key,
    required this.body,
    this.title,
    this.actions,
    this.bottom,
    this.showBack = true,
    this.padded = true,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool showBack;
  final bool padded;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = Breakpoints.isCompact(width) ? Space.lg : Space.xl;

    return Scaffold(
      backgroundColor: context.colors.surface,
      appBar: title == null
          ? null
          : AppBar(
              title: Text(title!),
              automaticallyImplyLeading: showBack,
              actions: actions,
            ),
      body: SafeArea(
        top: title == null,
        child: padded
            ? Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontal),
                child: body,
              )
            : body,
      ),
      bottomNavigationBar: bottom == null
          ? null
          : SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  Space.sm,
                  horizontal,
                  Space.lg,
                ),
                child: bottom,
              ),
            ),
    );
  }
}
