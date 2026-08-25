/// Domain enumerations. Pure Dart.
library;

/// The physical meter a user has. Drives the whole capture flow: an
/// unmetered user has nothing to read, and a prepaid meter counts *down*.
enum MeterType {
  prepaidKeypad,
  postpaidDigital,
  postpaidAnalogue,
  unmeteredEstimated;

  /// Prepaid meters display remaining units and decrement. Postpaid meters
  /// are cumulative and increment. Getting this backwards inverts every
  /// consumption figure in the product.
  MeterDirection get direction => switch (this) {
        MeterType.prepaidKeypad => MeterDirection.decrementing,
        MeterType.postpaidDigital => MeterDirection.incrementing,
        MeterType.postpaidAnalogue => MeterDirection.incrementing,
        MeterType.unmeteredEstimated => MeterDirection.none,
      };

  bool get isReadable => this != MeterType.unmeteredEstimated;
  bool get isPrepaid => this == MeterType.prepaidKeypad;

  String get label => switch (this) {
        MeterType.prepaidKeypad => 'Prepaid meter',
        MeterType.postpaidDigital => 'Postpaid digital meter',
        MeterType.postpaidAnalogue => 'Postpaid analogue meter',
        MeterType.unmeteredEstimated => 'No meter (estimated billing)',
      };

  String get description => switch (this) {
        MeterType.prepaidKeypad =>
          'You buy units and load them with a token. The meter counts down.',
        MeterType.postpaidDigital =>
          'A digital display that counts up. You get a bill.',
        MeterType.postpaidAnalogue =>
          'Spinning dials or a mechanical counter. You get a bill.',
        MeterType.unmeteredEstimated =>
          "You have no meter. The DisCo estimates your bill.",
      };
}

enum MeterDirection { incrementing, decrementing, none }

/// The 11 distribution companies, plus an escape hatch.
enum DisCo {
  abuja('Abuja Electricity Distribution Company', 'AEDC'),
  benin('Benin Electricity Distribution Company', 'BEDC'),
  eko('Eko Electricity Distribution Company', 'EKEDC'),
  enugu('Enugu Electricity Distribution Company', 'EEDC'),
  ibadan('Ibadan Electricity Distribution Company', 'IBEDC'),
  ikeja('Ikeja Electric', 'IE'),
  jos('Jos Electricity Distribution Company', 'JED'),
  kaduna('Kaduna Electricity Distribution Company', 'KAEDCO'),
  kano('Kano Electricity Distribution Company', 'KEDCO'),
  portHarcourt('Port Harcourt Electricity Distribution Company', 'PHED'),
  yola('Yola Electricity Distribution Company', 'YEDC'),
  other('Other', 'OTHER');

  const DisCo(this.label, this.code);
  final String label;
  final String code;
}

/// Service bands. Each carries a committed minimum daily supply, which is
/// the published standard a dispute is measured against.
enum TariffBand {
  a('A', 20),
  b('B', 16),
  c('C', 12),
  d('D', 8),
  e('E', 4);

  const TariffBand(this.label, this.committedHours);
  final String label;

  /// Committed minimum hours of supply per day.
  final int committedHours;

  String get commitment => 'Band $label promises $committedHours hours a day';
}

/// Whether the grid was up. `unknown` is a first-class state — it is what
/// makes a coverage figure honest, and coverage is what makes a dispute pack
/// credible.
enum SupplyState {
  available,
  unavailable,
  unknown;

  String get label => switch (this) {
        SupplyState.available => 'Power on',
        SupplyState.unavailable => 'Power off',
        SupplyState.unknown => 'No data',
      };
}

/// How a supply event was established. Inferred events are visually
/// distinguished everywhere, and manual entries supersede them on overlap.
enum SupplySource { inferredCharging, manual, imported }

/// What the platform could actually promise when a sample was recorded.
///
/// Recorded per event, not per device, because it changes: an Android user
/// who whitelists the app moves from periodic to continuous, and a dispute
/// pack spanning that boundary must report coverage honestly on both sides.
enum PlatformCapability {
  continuous,
  periodic,
  foregroundOnly;

  /// A rough expectation of how much of a window this capability can cover.
  /// Used only to explain coverage to the user, never to fabricate data.
  double get expectedCoverage => switch (this) {
        PlatformCapability.continuous => 0.95,
        PlatformCapability.periodic => 0.60,
        PlatformCapability.foregroundOnly => 0.25,
      };
}

enum ReadingSource { ocr, manual, imported }

/// Reasons a reading is excluded from baselines and trends. Flagged readings
/// stay visible in history — they are just not treated as clean data, and a
/// dispute pack either excludes them or shows the flag.
enum ReadingFlag {
  anomalousHigh(1 << 0),
  anomalousZero(1 << 1),
  rolloverOrReplacement(1 << 2),
  digitCountMismatch(1 << 3),
  lowOcrConfidence(1 << 4),
  userEdited(1 << 5),
  duplicateWindow(1 << 6);

  const ReadingFlag(this.bit);
  final int bit;

  /// Whether a flag disqualifies a reading from baseline computation.
  bool get excludesFromBaseline => switch (this) {
        ReadingFlag.anomalousHigh => true,
        ReadingFlag.anomalousZero => true,
        ReadingFlag.rolloverOrReplacement => true,
        ReadingFlag.digitCountMismatch => true,
        ReadingFlag.lowOcrConfidence => false,
        ReadingFlag.userEdited => false,
        ReadingFlag.duplicateWindow => false,
      };
}

extension ReadingFlagsBitmask on int {
  bool has(ReadingFlag flag) => this & flag.bit != 0;
  int withFlag(ReadingFlag flag) => this | flag.bit;
  int withoutFlag(ReadingFlag flag) => this & ~flag.bit;

  Set<ReadingFlag> get flags =>
      ReadingFlag.values.where((f) => has(f)).toSet();

  bool get excludedFromBaseline =>
      ReadingFlag.values.any((f) => has(f) && f.excludesFromBaseline);
}
