import '../entities/appliance.dart';
import '../value_objects/units.dart';

/// One appliance's modelled share of consumption.
class ApplianceAttribution {
  const ApplianceAttribution({
    required this.appliance,
    required this.modelledDaily,
    required this.share,
  });

  final Appliance appliance;
  final Kwh modelledDaily;

  /// Share of the modelled total, 0–1.
  final double share;

  /// Share of the *measured* total after normalisation, 0–1.
  double normalisedShare(double normalisationFactor) =>
      share * normalisationFactor;
}

class LoadModel {
  const LoadModel({
    required this.attributions,
    required this.modelledDailyTotal,
    required this.measuredDailyTotal,
    required this.divergence,
  });

  final List<ApplianceAttribution> attributions;
  final Kwh modelledDailyTotal;
  final Kwh? measuredDailyTotal;

  /// (modelled - measured) / measured. Positive means the model claims more
  /// than the meter saw.
  final double? divergence;

  /// Beyond this the model and the meter disagree enough to be worth asking
  /// the user about.
  static const double reconciliationThreshold = 0.25;

  bool get needsReconciliation =>
      divergence != null && divergence!.abs() > reconciliationThreshold;

  /// Whether the model claims *less* than the meter measured — meaning
  /// something is drawing power the user has not told us about.
  bool get hasUnaccountedLoad =>
      divergence != null && divergence! < -reconciliationThreshold;
}

/// Models where consumption goes.
///
/// Everything this produces is an estimate and the API says so: the entity
/// is called a model, the fields are called `modelled`, and the divergence
/// against measurement is always returned so the UI can be honest about how
/// well the two agree.
class LoadModelEngine {
  const LoadModelEngine();

  LoadModel model({
    required List<Appliance> appliances,
    required double supplyHoursPerDay,
    Kwh? measuredDailyTotal,
  }) {
    if (appliances.isEmpty) {
      return LoadModel(
        attributions: const [],
        modelledDailyTotal: Kwh.zero,
        measuredDailyTotal: measuredDailyTotal,
        divergence: null,
      );
    }

    final modelled = <Appliance, Kwh>{
      for (final a in appliances)
        a: a.modelledDailyKwhWithSupply(supplyHoursPerDay),
    };

    final total = modelled.values.fold<Kwh>(Kwh.zero, (a, k) => a + k);

    final attributions = [
      for (final entry in modelled.entries)
        ApplianceAttribution(
          appliance: entry.key,
          modelledDaily: entry.value,
          share: total.isZero ? 0 : entry.value.milli / total.milli,
        ),
    ]..sort((a, b) => b.modelledDaily.milli.compareTo(a.modelledDaily.milli));

    double? divergence;
    if (measuredDailyTotal != null && !measuredDailyTotal.isZero) {
      divergence =
          (total.milli - measuredDailyTotal.milli) / measuredDailyTotal.milli;
    }

    return LoadModel(
      attributions: attributions,
      modelledDailyTotal: total,
      measuredDailyTotal: measuredDailyTotal,
      divergence: divergence,
    );
  }

  /// Factor that scales modelled shares onto the measured total, so the
  /// percentages the user sees add up against what the meter actually said.
  double normalisationFactor(LoadModel model) {
    final measured = model.measuredDailyTotal;
    if (measured == null || model.modelledDailyTotal.isZero) return 1;
    return measured.milli / model.modelledDailyTotal.milli;
  }
}
