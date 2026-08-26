import 'dart:io';

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
import '../application/capture_controller.dart';
import '../application/reading_controller.dart';
import '../widgets/numeric_keypad.dart';

/// Confirms what the camera read.
///
/// The extracted digits and the photograph sit on one screen, so the user
/// compares them without navigating. Characters the recogniser was unsure of
/// are marked, so the user checks *those* rather than re-reading the whole
/// number. Nothing is ever committed silently (FR-2.2).
class ConfirmReadingScreen extends ConsumerStatefulWidget {
  const ConfirmReadingScreen({super.key, required this.capture});

  final CaptureResult capture;

  @override
  ConsumerState<ConfirmReadingScreen> createState() =>
      _ConfirmReadingScreenState();
}

class _ConfirmReadingScreenState extends ConsumerState<ConfirmReadingScreen> {
  late String _entry = widget.capture.reading?.digits ?? '';
  late final bool _prefilled = _entry.isNotEmpty;
  bool _edited = false;
  bool _saving = false;

  /// Set once the photograph belongs to a saved reading. Until then, leaving
  /// this screen by any route — Retake, the back button, or the system back
  /// gesture — discards it. Storage is scarce on the devices this ships to,
  /// and abandoned captures would accumulate silently.
  bool _committed = false;

  @override
  void dispose() {
    if (!_committed) {
      ref
          .read(captureControllerProvider.notifier)
          .discard(widget.capture.photoPath);
    }
    super.dispose();
  }

  Kwh? get _value {
    if (_entry.isEmpty) return null;
    final parsed = double.tryParse(_entry);
    return parsed == null ? null : Kwh.fromDouble(parsed);
  }

  void _change(String next) => setState(() {
        _entry = next;
        _edited = true;
      });

  @override
  Widget build(BuildContext context) {
    final meter = ref.watch(selectedMeterProvider);
    final c = context.colors;
    final t = context.type;

    if (meter == null) {
      return const GridScaffold(title: 'Check the reading', body: SizedBox.shrink());
    }

    final value = _value;
    final outcome = value == null
        ? ValidationOutcome.clean
        : ref.watch(
            candidateValidationProvider((meterId: meter.id, value: value)),
          );
    final reading = widget.capture.reading;

    return GridScaffold(
      title: 'Check the reading',
      padded: false,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
        children: [
          // The photograph, so the digits can be checked against the meter
          // without leaving the screen.
          ClipRRect(
            borderRadius: Radii.mdAll,
            child: Image.file(
              File(widget.capture.photoPath),
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                height: 160,
                color: c.surfaceDim,
                alignment: Alignment.center,
                child: Icon(Icons.image_not_supported_rounded,
                    color: c.textTertiary),
              ),
            ),
          ),
          const SizedBox(height: Space.lg),

          if (!_prefilled)
            InfoNote(
              icon: Icons.edit_rounded,
              message: "Couldn't read that clearly — type the numbers in and "
                  "Grid keeps the photo either way.",
            )
          else if (reading != null && reading.uncertainPositions.isNotEmpty)
            InfoNote(
              tone: NoteTone.warning,
              message: 'Check the underlined digits — those are the ones Grid '
                  'is least sure about.',
            ),

          const SizedBox(height: Space.lg),
          _ReadingField(
            entry: _entry,
            uncertain: _edited
                ? const <int>{}
                : (reading?.uncertainPositions ?? const <int>{}),
          ),
          const SizedBox(height: Space.md),

          Row(
            children: [
              Icon(Icons.timer_outlined, size: 14, color: c.textTertiary),
              const SizedBox(width: Space.xs),
              Text(
                _prefilled
                    ? 'Read in ${widget.capture.elapsed.inMilliseconds} ms'
                    : 'Photo saved',
                style: t.caption.copyWith(color: c.textTertiary),
              ),
            ],
          ),

          if (!outcome.isClean) ...[
            const SizedBox(height: Space.lg),
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

          const SizedBox(height: Space.lg),
          NumericKeypad(
            onDigit: (d) => _change(_entry + d),
            onDecimal: () {
              if (!_entry.contains('.')) {
                _change(_entry.isEmpty ? '0.' : '$_entry.');
              }
            },
            onBackspace: () {
              if (_entry.isNotEmpty) {
                _change(_entry.substring(0, _entry.length - 1));
              }
            },
          ),
        ],
      ),
      bottom: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving ? null : _discard,
              child: const Text('Retake'),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: (value == null || outcome.isBlocked || _saving)
                  ? null
                  : () => _save(meter.id, value, outcome),
              child: Text(
                outcome.isClean || outcome.isBlocked
                    ? 'Save reading'
                    : 'Save anyway',
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Retake. `dispose` does the deleting, so this only has to leave.
  void _discard() => context.pop();

  Future<void> _save(
    String meterId,
    Kwh value,
    ValidationOutcome outcome,
  ) async {
    setState(() => _saving = true);
    final reading = widget.capture.reading;

    // Hand the photograph over to the reading before leaving, so dispose does
    // not delete a file the saved record now points at.
    _committed = true;

    await ref.read(readingControllerProvider.notifier).add(
          meterId: meterId,
          value: value,
          // A reading the user retyped is a manual reading, whatever the
          // camera first suggested. Recording it as OCR would overstate how
          // well recognition is working.
          source: _edited ? ReadingSource.manual : ReadingSource.ocr,
          flags: outcome.flagsIfConfirmed,
          ocrConfidence: _edited ? null : reading?.confidence,
          photoPath: widget.capture.photoPath,
        );
    if (!mounted) return;
    context.go('/');
  }
}

/// The reading, with uncertain characters underlined individually.
class _ReadingField extends StatelessWidget {
  const _ReadingField({required this.entry, required this.uncertain});

  final String entry;
  final Set<int> uncertain;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = context.type;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.xl,
      ),
      decoration: BoxDecoration(
        color: c.surfaceDim,
        borderRadius: Radii.mdAll,
        border: Border.all(color: c.outlineStrong),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          if (entry.isEmpty)
            Text('0', style: t.meter.copyWith(color: c.textTertiary))
          else
            Semantics(
              label: uncertain.isEmpty
                  ? 'Reading $entry'
                  : 'Reading $entry. Some digits are uncertain, please check',
              child: RichText(
                // RichText does not inherit MediaQuery.textScaler the way
                // Text does, so without this the reading is the one thing on
                // the screen that ignores the user's text size.
                textScaler: MediaQuery.textScalerOf(context),
                text: TextSpan(
                  children: [
                    for (var i = 0; i < entry.length; i++)
                      TextSpan(
                        text: entry[i],
                        style: uncertain.contains(i)
                            ? t.meter.copyWith(
                                color: c.warning,
                                decoration: TextDecoration.underline,
                                decorationStyle: TextDecorationStyle.dotted,
                                decorationColor: c.warning,
                                decorationThickness: 2,
                              )
                            : t.meter,
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(width: Space.sm),
          Text('kWh', style: t.label.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}
