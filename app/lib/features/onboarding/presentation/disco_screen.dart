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

class DiscoScreen extends ConsumerStatefulWidget {
  const DiscoScreen({super.key});

  @override
  ConsumerState<DiscoScreen> createState() => _DiscoScreenState();
}

class _DiscoScreenState extends ConsumerState<DiscoScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(onboardingControllerProvider).disco;
    final t = context.type;
    final c = context.colors;

    final matches = DisCo.values
        .where((d) =>
            _query.isEmpty ||
            d.label.toLowerCase().contains(_query.toLowerCase()) ||
            d.code.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return GridScaffold(
      step: 2,
      totalSteps: 3,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: Space.xl),
          Text('Who supplies your electricity?', style: t.headline),
          const SizedBox(height: Space.sm),
          Text(
            "It's on your bill or your meter card.",
            style: t.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
          const SizedBox(height: Space.lg),
          Expanded(
            child: ListView.separated(
              itemCount: matches.length,
              separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
              itemBuilder: (context, i) {
                final disco = matches[i];
                return SelectableCard(
                  title: disco.label,
                  subtitle: disco.code,
                  selected: selected == disco,
                  onTap: () => ref
                      .read(onboardingControllerProvider.notifier)
                      .setDisco(disco),
                );
              },
            ),
          ),
        ],
      ),
      bottom: FilledButton(
        onPressed:
            selected == null ? null : () => context.go(Routes.onboardingBand),
        child: const Text('Continue'),
      ),
    );
  }
}
