import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../domain/services/validation_engine.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';
import '../application/reading_controller.dart';
import '../widgets/numeric_keypad.dart';

/// Manual reading entry.
///
/// Uses the large custom keypad rather than the system keyboard, because
/// this flow runs outdoors, one-handed, often in the dark.
class ManualEntryScreen extends ConsumerStatefulWidget {
  const ManualEntryScreen({super.key});

  @override
  ConsumerState<ManualEntryScreen> createState() => _ManualEntryScreenState();
}

class _ManualEntryScreenState extends ConsumerState<ManualEntryScreen> {
  String _entry = '';
  bool _saving = false;

  Kwh? get _value {
    if (_entry.isEmpty) return null;
    final parsed = double.tryParse(_entry);
    return parsed == null ? null : Kwh.fromDouble(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final meter = ref.watch(selectedMeterProvider);
    final t = context.type;
    final c = context.colors;

    if (meter == null) {
      return const GridScaffold(title: 'Log reading', body: SizedBox.shrink());
    }

    final value = _value;
    final outcome = value == null
        ? ValidationOutcome.clean
        : ref.watch(
            candidateValidationProvider((meterId: meter.id, value: value)),
          );

    return GridScaffold(
      title: 'Log reading',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Space.lg),
          Text(
            meter.isPrepaid
                ? 'What does your meter show now?'
                : 'What is the reading on your meter?',
            style: t.body.copyWith(color: c.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: Space.lg,
              vertical: Space.xl,
            ),
            decoration: BoxDecoration(
              color: c.surfaceDim,
              borderRadius: Radii.mdAll,
              border: Border.all(color: c.outline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  _entry.isEmpty ? '0' : _entry,
                  style: t.meter.copyWith(
                    color: _entry.isEmpty ? c.textTertiary : c.textPrimary,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Text('kWh', style: t.label.copyWith(color: c.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),

          // Warnings are inline, above the confirm button, never a modal.
          // The primary action stays enabled throughout.
          // Warnings scroll in whatever space is left above the keypad. The
          // bottom padding keeps a partially-scrolled card from sitting flush
          // against the keys, where a clipped card reads as broken rather
          // than as scrollable.
          if (!outcome.isClean)
            Expanded(
              child: ShaderMask(
                shaderCallback: (rect) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    c.surface,
                    c.surface,
                    c.surface.withValues(alpha: 0),
                  ],
                  stops: const [0, 0.88, 1],
                ).createShader(rect),
                blendMode: BlendMode.dstIn,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: Space.xl),
                  children: [
                    for (final w in outcome.warnings) ...[
                      InfoNote(
                        tone: switch (w.severity) {
                          WarningSeverity.info => NoteTone.neutral,
                          WarningSeverity.caution => NoteTone.warning,
                          WarningSeverity.serious => NoteTone.danger,
                        },
                        message: w.message,
                      ),
                      const SizedBox(height: Space.sm),
                    ],
                  ],
                ),
              ),
            )
          else
            const Spacer(),

          NumericKeypad(
            onDigit: (d) => setState(() => _entry += d),
            onDecimal: () => setState(() {
              if (!_entry.contains('.')) {
                _entry = _entry.isEmpty ? '0.' : '$_entry.';
              }
            }),
            onBackspace: () => setState(() {
              if (_entry.isNotEmpty) {
                _entry = _entry.substring(0, _entry.length - 1);
              }
            }),
          ),
          const SizedBox(height: Space.lg),
        ],
      ),
      bottom: FilledButton(
        onPressed: (value == null || outcome.isBlocked || _saving)
            ? null
            : () => _save(meter.id, value, outcome),
        child: Text(
          outcome.isClean || outcome.isBlocked ? 'Save reading' : 'Save anyway',
        ),
      ),
    );
  }

  Future<void> _save(
    String meterId,
    Kwh value,
    ValidationOutcome outcome,
  ) async {
    setState(() => _saving = true);
    await ref.read(readingControllerProvider.notifier).add(
          meterId: meterId,
          value: value,
          source: ReadingSource.manual,
          flags: outcome.flagsIfConfirmed,
        );
    if (!mounted) return;
    context.pop();
  }
}
