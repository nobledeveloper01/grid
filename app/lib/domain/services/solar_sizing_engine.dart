import '../value_objects/units.dart';

/// Sizing a solar and battery system from what this household actually
/// measured, rather than from what a vendor assumed.
///
/// Feature F10. Solar sizing in this market is done by the person selling the
/// system, from a guess about the customer's load, and the answer is
/// reliably the size they happen to stock. By the time this runs Grid has
/// months of measured consumption, a measured outage profile, and — from F9 —
/// what the household actually spends on fuel. That is a better input than the
/// professional has, which is the only reason this feature is defensible.
///
/// It is still an estimate, and the result says so in its own fields rather
/// than in a footnote.
sealed class SolarSizing {
  const SolarSizing();
}

enum SizingGap {
  /// Not enough consumption history to size anything.
  notEnoughConsumption,

  /// The supply log has not observed enough to state an outage profile, and
  /// the battery is sized on outages.
  notEnoughSupply,

  /// A household with essentially no outages does not need this system, and
  /// sizing one would be selling it something.
  noMeaningfulOutages,
}

class SizingUnavailable extends SolarSizing {
  const SizingUnavailable(this.reason, this.detail);

  final SizingGap reason;
  final String detail;
}

class Sized extends SolarSizing {
  const Sized({
    required this.dailyKwh,
    required this.panelKw,
    required this.batteryKwh,
    required this.inverterKw,
    required this.longestOutageHours,
    required this.meanOutageHoursPerDay,
    required this.daysMeasured,
    required this.coverage,
    required this.payback,
    required this.unknowns,
  });

  /// Measured daily consumption this is sized against.
  final Kwh dailyKwh;

  /// Array size. Sized to replace the household's own daily consumption at a
  /// conservative yield, not to fill a roof.
  final double panelKw;

  /// Usable storage, sized on the **longest** measured outage rather than the
  /// average one — an average-sized battery is flat exactly on the days the
  /// household bought it for.
  final double batteryKwh;

  /// Continuous inverter rating.
  final double inverterKw;

  final double longestOutageHours;
  final double meanOutageHoursPerDay;

  /// How many usable days the sizing rests on.
  final int daysMeasured;

  /// Proportion of the window the supply log observed.
  final double coverage;

  /// Null when there is no logged generator spend to pay back against. A
  /// payback figure invented from an assumed fuel bill is exactly the vendor
  /// behaviour this feature exists to replace.
  final SolarPayback? payback;

  /// What this estimate does not know, in the user's words, shown beside the
  /// recommendation rather than under it.
  final List<String> unknowns;

  bool get isRough => daysMeasured < 30;
}

class SolarPayback {
  const SolarPayback({
    required this.monthlyGeneratorSpend,
    required this.systemCostLow,
    required this.systemCostHigh,
    required this.monthsLow,
    required this.monthsHigh,
  });

  /// Measured, from logged fuel purchases.
  final Naira monthlyGeneratorSpend;

  /// A range, because installed prices vary by more than any single figure
  /// could honestly represent.
  final Naira systemCostLow;
  final Naira systemCostHigh;

  final int monthsLow;
  final int monthsHigh;
}

class SolarSizingEngine {
  const SolarSizingEngine();

  /// Peak-sun hours a day. Conservative for southern Nigeria; the north does
  /// better. Being wrong in this direction oversizes the array slightly,
  /// which fails safe.
  static const double peakSunHours = 4.0;

  /// Losses between panel and load: inverter, wiring, temperature, dust.
  static const double systemEfficiency = 0.75;

  /// Lithium is routinely specified to 80% depth of discharge. Sizing to
  /// 100% is how a battery bank reaches end of life in two years.
  static const double usableDepthOfDischarge = 0.80;

  /// Below this, a household is not buying a system to ride out outages.
  static const double meaningfulOutageHours = 2.0;

  static const int minimumUsableDays = 14;
  static const double minimumCoverage = 0.60;

  /// Installed cost **in naira** per kW of array, low and high. Wide on
  /// purpose: installed prices vary by more than any single figure could
  /// honestly represent, and they move with the exchange rate.
  static const int costPerKwLow = 850000;
  static const int costPerKwHigh = 1400000;

  /// And in naira per usable kWh of storage.
  static const int costPerKwhLow = 450000;
  static const int costPerKwhHigh = 750000;

  SolarSizing size({
    required Kwh dailyKwh,
    required double longestOutageHours,
    required double meanOutageHoursPerDay,
    required int daysMeasured,
    required double coverage,
    Naira? monthlyGeneratorSpend,
  }) {
    if (dailyKwh.isZero || daysMeasured < minimumUsableDays) {
      return SizingUnavailable(
        SizingGap.notEnoughConsumption,
        'Grid needs about a fortnight of readings before it can size a system '
        'against what you actually use. It has $daysMeasured days.',
      );
    }
    if (coverage < minimumCoverage) {
      return SizingUnavailable(
        SizingGap.notEnoughSupply,
        'The power log covers ${(coverage * 100).round()}% of the period. The '
        'battery is sized on how long your outages run, so that has to be '
        'measured rather than guessed.',
      );
    }
    if (longestOutageHours < meaningfulOutageHours) {
      return SizingUnavailable(
        SizingGap.noMeaningfulOutages,
        'Your longest measured outage is under two hours. A battery system '
        'sized for that would be selling you something you do not need.',
      );
    }

    // Array: replace a day's consumption, allowing for losses.
    final panelKw = dailyKwh.value / (peakSunHours * systemEfficiency);

    // Storage: carry the household through its worst measured outage, at the
    // rate it actually draws, and only to a safe depth of discharge.
    final drawPerHour = dailyKwh.value / 24.0;
    final batteryKwh =
        (drawPerHour * longestOutageHours) / usableDepthOfDischarge;

    // Inverter: continuous draw with headroom for the surges a pumping
    // machine and a compressor make when they start.
    final inverterKw = drawPerHour * 3.0;

    return Sized(
      dailyKwh: dailyKwh,
      panelKw: _round(panelKw),
      batteryKwh: _round(batteryKwh),
      inverterKw: _round(inverterKw),
      longestOutageHours: longestOutageHours,
      meanOutageHoursPerDay: meanOutageHoursPerDay,
      daysMeasured: daysMeasured,
      coverage: coverage,
      payback: monthlyGeneratorSpend == null || monthlyGeneratorSpend.isZero
          ? null
          : _payback(
              panelKw: _round(panelKw),
              batteryKwh: _round(batteryKwh),
              monthly: monthlyGeneratorSpend,
            ),
      unknowns: const [
        'Whether your roof has the space and the orientation for the array.',
        'Shading — a single tree or a neighbouring block changes the yield '
            'more than any figure here.',
        'Installed prices, which vary by more than the range shown and move '
            'with the exchange rate.',
        'What you would still run off the grid, which changes the payback.',
      ],
    );
  }

  SolarPayback _payback({
    required double panelKw,
    required double batteryKwh,
    required Naira monthly,
  }) {
    // Naira, not kobo — `fromNaira` does the conversion. Dividing by 100 here
    // as well priced a 3.3 kW array with storage at ₦44,000 and produced a
    // two-month payback, which is the kind of number a reader believes for
    // exactly as long as it takes to think about it.
    final low = Naira.fromNaira(
      panelKw * costPerKwLow + batteryKwh * costPerKwhLow,
    );
    final high = Naira.fromNaira(
      panelKw * costPerKwHigh + batteryKwh * costPerKwhHigh,
    );
    return SolarPayback(
      monthlyGeneratorSpend: monthly,
      systemCostLow: low,
      systemCostHigh: high,
      monthsLow: (low.kobo / monthly.kobo).ceil(),
      monthsHigh: (high.kobo / monthly.kobo).ceil(),
    );
  }

  /// One decimal. A sizing quoted to three is a sizing pretending to a
  /// precision none of its inputs have.
  static double _round(double v) => (v * 10).round() / 10;
}
