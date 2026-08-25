import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../features/meter/application/meter_providers.dart';
import '../../../shared/widgets/grid_scaffold.dart';

/// The payoff screen, immediately after the meter is created.
///
/// The product's promise, stated once, in plain words. This is the one place
/// motion is emphasised — it earns the extra 600ms.
class FirstValueScreen extends ConsumerWidget {
  const FirstValueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    final t = context.type;
    final c = context.colors;

    final (headline, body) = switch (meter?.type) {
      MeterType.prepaidKeypad => (
          'Never run out unexpectedly again',
          "Log your meter reading and Grid works out when your units finish — "
              "and warns you three days before.",
        ),
      MeterType.unmeteredEstimated => (
          'Estimated bills, finally contestable',
          "Tell Grid what you run and for how long. It works out what you "
              "actually use — which is what a dispute needs.",
        ),
      _ => (
          'Know what your bill will be',
          "Log your meter reading and Grid projects your bill before it "
              "arrives — and keeps the evidence if it's wrong.",
        ),
    };

    return GridScaffold(
      showBack: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Motion.firstValue,
            curve: Curves.easeOutQuart,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.translate(
                offset: Offset(0, (1 - v) * 16),
                child: child,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.bolt, size: 56, color: c.accent),
                const SizedBox(height: Space.xl),
                Text(headline, style: t.headline),
                const SizedBox(height: Space.md),
                Text(
                  body,
                  style: t.body.copyWith(color: c.textSecondary),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            "Grid works with no internet. Nothing you log leaves your phone "
            "unless you choose to share it.",
            style: t.caption.copyWith(color: c.textTertiary),
          ),
          const SizedBox(height: Space.lg),
        ],
      ),
      bottom: FilledButton(
        onPressed: () => context.go(Routes.home),
        child: const Text('Log my first reading'),
      ),
    );
  }
}
