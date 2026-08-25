import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/router.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/selectable_card.dart';
import '../application/onboarding_controller.dart';

/// The first screen on first launch.
///
/// No splash, no carousel, no login wall, and no permission request — the
/// user is asked one question they can answer by looking at their wall.
class MeterTypeScreen extends ConsumerWidget {
  const MeterTypeScreen({super.key});

  static const _icons = {
    MeterType.prepaidKeypad: Icons.dialpad,
    MeterType.postpaidDigital: Icons.confirmation_number_outlined,
    MeterType.postpaidAnalogue: Icons.speed,
    MeterType.unmeteredEstimated: Icons.help_outline,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(onboardingControllerProvider).type;
    final t = context.type;
    final c = context.colors;

    return GridScaffold(
      showBack: false,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Space.xxl),
          Text('What kind of meter do you have?', style: t.headline),
          const SizedBox(height: Space.sm),
          Text(
            'Have a look at your meter. This decides how Grid reads it.',
            style: t.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.xl),
          Expanded(
            child: ListView.separated(
              itemCount: MeterType.values.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.md),
              itemBuilder: (context, i) {
                final type = MeterType.values[i];
                return SelectableCard(
                  title: type.label,
                  subtitle: type.description,
                  icon: _icons[type],
                  selected: selected == type,
                  onTap: () => ref
                      .read(onboardingControllerProvider.notifier)
                      .setType(type),
                );
              },
            ),
          ),
        ],
      ),
      bottom: FilledButton(
        onPressed: selected == null
            ? null
            : () => context.go(Routes.onboardingDisco),
        child: const Text('Continue'),
      ),
    );
  }
}
