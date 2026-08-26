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
    this.step,
    this.totalSteps,
  });

  final Widget body;
  final String? title;
  final List<Widget>? actions;
  final Widget? bottom;
  final bool showBack;
  final bool padded;

  /// 1-based position in a multi-step flow. A flow with more than one step
  /// should say how many are left; guessing is a small anxiety the user does
  /// not need while being asked about their meter.
  final int? step;
  final int? totalSteps;

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
        child: Column(
          children: [
            if (step != null && totalSteps != null)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontal,
                  Space.lg,
                  horizontal,
                  0,
                ),
                child: _StepIndicator(step: step!, total: totalSteps!),
              ),
            Expanded(
              // The wash sits *inside* the scrolling area, at its bottom
              // edge. It used to be painted on the bottom bar, which is laid
              // out below the body rather than over it — so it faded nothing
              // and content still clipped hard, mid-row, at the boundary.
              child: Stack(
                children: [
                  Positioned.fill(
                    child: padded
                        ? Padding(
                            padding:
                                EdgeInsets.symmetric(horizontal: horizontal),
                            child: body,
                          )
                        : body,
                  ),
                  if (bottom != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 32,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                context.colors.surface.withValues(alpha: 0),
                                context.colors.surface,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: bottom == null
          ? null
          : ColoredBox(
              color: context.colors.surface,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    Space.lg,
                    horizontal,
                    Space.lg,
                  ),
                  child: bottom,
                ),
              ),
            ),
    );
  }
}

/// Progress through a multi-step flow. Segments rather than dots, so the
/// proportion completed is readable at a glance and not just countable.
class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step, required this.total});

  final int step;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Step $step of $total',
      child: ExcludeSemantics(
        child: Row(
          children: [
            for (var i = 1; i <= total; i++) ...[
              Expanded(
                child: AnimatedContainer(
                  duration: Motion.page,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? c.brand : c.track,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              if (i != total) const SizedBox(width: Space.xs),
            ],
          ],
        ),
      ),
    );
  }
}
