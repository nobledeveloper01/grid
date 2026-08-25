import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/providers.dart';
import '../../../domain/entities/reading.dart';
import '../../../domain/services/validation_engine.dart';
import '../../../domain/value_objects/enums.dart';
import '../../../domain/value_objects/units.dart';
import '../../meter/application/meter_providers.dart';

/// Validates a candidate reading against history, live as the user types.
///
/// Warnings are advisory. Nothing here blocks except an out-of-order
/// reading, which would corrupt every derived figure.
final candidateValidationProvider =
    Provider.family<ValidationOutcome, ({String meterId, Kwh value})>(
        (ref, args) {
  final meter = ref
      .watch(metersProvider)
      .value
      ?.where((m) => m.id == args.meterId)
      .firstOrNull;
  if (meter == null) return ValidationOutcome.clean;

  final readings = ref.watch(readingsProvider(args.meterId)).value;
  final purchases = ref.watch(purchasesProvider(args.meterId)).value;
  if (readings == null || purchases == null) return ValidationOutcome.clean;

  final now = ref.watch(clockProvider)();
  final mean = ref.watch(consumptionEngineProvider).rollingDailyMean(
        meter: meter,
        readings: readings,
        purchases: purchases,
        now: now,
      );

  return ref.watch(validationEngineProvider).validate(
        meter: meter,
        candidate: args.value,
        readAt: now,
        history: readings,
        rollingDailyMeanKwh: mean,
      );
});

class ReadingController extends Notifier<void> {
  @override
  void build() {}

  /// Commits a reading. Writes locally and returns; there is nothing to
  /// await beyond the disk, and the UI updates from the Drift stream.
  Future<void> add({
    required String meterId,
    required Kwh value,
    required ReadingSource source,
    int flags = 0,
    double? ocrConfidence,
    String? photoPath,
    String? note,
  }) async {
    final now = ref.read(clockProvider)();
    final reading = Reading(
      id: ref.read(uuidProvider).v7(),
      meterId: meterId,
      value: value,
      readAt: now,
      recordedAt: now,
      source: source,
      flags: flags,
      ocrConfidence: ocrConfidence,
      photoPath: photoPath,
      note: note,
    );
    await ref.read(readingRepositoryProvider).add(reading);
  }

  Future<void> addPurchase({
    required String meterId,
    required Naira amount,
    Kwh? units,
    String? tokenRef,
  }) async {
    final rate = ref.read(effectiveRateProvider(meterId));
    final derived = units == null && rate != null;

    await ref.read(purchaseRepositoryProvider).add(
          Purchase(
            id: ref.read(uuidProvider).v7(),
            meterId: meterId,
            amount: amount,
            units: units ?? rate?.energyFor(amount),
            unitsDerived: derived,
            purchasedAt: ref.read(clockProvider)(),
            tokenRef: tokenRef,
          ),
        );
  }
}

final readingControllerProvider =
    NotifierProvider<ReadingController, void>(ReadingController.new);
