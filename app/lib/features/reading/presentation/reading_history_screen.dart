import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../core/theme/theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../domain/value_objects/units.dart';
import '../../../shared/widgets/figure.dart';
import '../../../shared/widgets/grid_scaffold.dart';
import '../../../shared/widgets/info_note.dart';
import '../../meter/application/meter_providers.dart';

/// Chronological reading history.
///
/// Flagged readings stay visible — they are simply not treated as clean
/// data. Hiding them would make the record less honest, and the record is
/// the product.
class ReadingHistoryScreen extends ConsumerWidget {
  const ReadingHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meter = ref.watch(selectedMeterProvider);
    final t = context.type;
    final c = context.colors;

    if (meter == null) {
      return const GridScaffold(title: 'Readings', body: SizedBox.shrink());
    }

    final readings = ref.watch(readingsProvider(meter.id)).value ?? const [];
    final now = ref.watch(clockProvider)();

    if (readings.isEmpty) {
      return const GridScaffold(
        title: 'Readings',
        body: Padding(
          padding: EdgeInsets.only(top: Space.xl),
          child: InfoNote(
            message: 'No readings yet. Log one from the home screen and your '
                'record starts here.',
          ),
        ),
      );
    }

    return GridScaffold(
      title: 'Readings',
      body: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: Space.lg),
        itemCount: readings.length,
        separatorBuilder: (_, _) => const SizedBox(height: Space.sm),
        itemBuilder: (context, i) {
          final r = readings[i];
          final flags = r.flagSet;

          return Container(
            padding: const EdgeInsets.all(Space.lg),
            decoration: BoxDecoration(
              color: c.surfaceDim,
              borderRadius: Radii.mdAll,
              border: Border.all(
                color: r.isSuperseded ? c.outline : Colors.transparent,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: r.isSuperseded
                          ? Text(
                              r.value.format(),
                              style: t.figure.copyWith(
                                color: c.textTertiary,
                                decoration: TextDecoration.lineThrough,
                              ),
                            )
                          : Figure(
                              value: r.value.formatValue(),
                              unit: Kwh.unit,
                            ),
                    ),
                    Icon(
                      switch (r.source) {
                        ReadingSource.ocr => Icons.camera_alt_outlined,
                        ReadingSource.manual => Icons.edit_outlined,
                        ReadingSource.imported => Icons.download_outlined,
                      },
                      size: 18,
                      color: c.textTertiary,
                    ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(
                  '${friendlyDate(r.readAt, now: now)} · '
                  '${relativeTime(r.readAt, now: now)}',
                  style: t.caption.copyWith(color: c.textSecondary),
                ),
                if (flags.isNotEmpty) ...[
                  const SizedBox(height: Space.sm),
                  Wrap(
                    spacing: Space.xs,
                    runSpacing: Space.xs,
                    children: [
                      for (final f in flags)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Space.sm,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: Radii.smAll,
                            border: Border.all(color: c.warning),
                          ),
                          child: Text(
                            _flagLabel(f),
                            style: t.caption.copyWith(color: c.warning),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  static String _flagLabel(ReadingFlag f) => switch (f) {
        ReadingFlag.anomalousHigh => 'Unusually high',
        ReadingFlag.anomalousZero => 'No usage recorded',
        ReadingFlag.rolloverOrReplacement => 'Meter changed',
        ReadingFlag.digitCountMismatch => 'Digit count differs',
        ReadingFlag.lowOcrConfidence => 'Hard to read',
        ReadingFlag.userEdited => 'Edited',
        ReadingFlag.duplicateWindow => 'Repeat',
      };
}
