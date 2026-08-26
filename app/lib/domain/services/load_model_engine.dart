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
/// One appliance, priced, with the what-if attached.
class ApplianceCost {
  const ApplianceCost({
    required this.attribution,
    required this.monthlyCost,
    required this.rate,
    required this.daysPerMonth,
    required this.normalisation,
  });

  final ApplianceAttribution attribution;

  /// What it is modelled to cost a month at the rate in force.
  final Naira monthlyCost;

  final Rate rate;
  final int daysPerMonth;

  /// The factor applied to bring the model onto the measured total. Carried
  /// so a screen can say the figures are pegged to the meter rather than to
  /// the inventory.
  final double normalisation;

  Appliance get appliance => attribution.appliance;

  /// What a month costs if this appliance runs [hours] fewer per day.
  ///
  /// Clamped at zero rather than going negative: asking what happens if a
  /// fridge runs 30 hours a day less is a reasonable thing for a slider to
  /// do and an unreasonable thing to answer with a refund.
  Naira savingFromRunningLess(double hours) {
    final current = appliance.hoursPerDay;
    final reduced = (current - hours).clamp(0.0, current);
    final saved = current <= 0 ? 0.0 : (current - reduced) / current;
    return Naira.fromKobo((monthlyCost.kobo * saved).round());
  }
}

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

  /// What each appliance costs a month, and what changing its hours would do.
  ///
  /// Feature F12. Without this the inventory is data entry the user did for
  /// the app's benefit rather than their own — the attribution chart shows
  /// where the units go and stops one step short of what to do about it.
  ///
  /// Shares are normalised onto the **measured** total where there is one, so
  /// the naira figures add up against the meter rather than against the model.
  /// A model that is 30% high would otherwise quote 30% more savings than the
  /// household could actually make, which is the direction that gets somebody
  /// to switch something off and see no change on the bill.
  List<ApplianceCost> coach({
    required LoadModel model,
    required Rate rate,
    int daysPerMonth = 30,
  }) {
    if (model.attributions.isEmpty) return const [];
    final factor = normalisationFactor(model);

    return [
      for (final a in model.attributions)
        ApplianceCost(
          attribution: a,
          monthlyCost: rate.costOf(
            Kwh.fromMilli(
              (a.modelledDaily.milli * factor * daysPerMonth).round(),
            ),
          ),
          rate: rate,
          daysPerMonth: daysPerMonth,
          normalisation: factor,
        ),
    ];
  }

  /// Factor that scales modelled shares onto the measured total, so the
  /// percentages the user sees add up against what the meter actually said.
  double normalisationFactor(LoadModel model) {
    final measured = model.measuredDailyTotal;
    if (measured == null || model.modelledDailyTotal.isZero) return 1;
    return measured.milli / model.modelledDailyTotal.milli;
  }
}
