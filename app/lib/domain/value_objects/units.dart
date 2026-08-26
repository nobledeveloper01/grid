/// Energy and money value objects.
///
/// Both are stored as integers throughout — never floats. Energy in
/// milli-kWh, money in kobo. Floating point on money produces rounding
/// drift, and in a product whose whole purpose is producing an arithmetic
/// record that survives a dispute, drift is unacceptable.
library;

/// Energy, held as milli-kWh (kWh x 1000).
extension type const Kwh._(int milli) implements Object {
  const Kwh.fromMilli(int milli) : this._(milli);
  Kwh.fromDouble(double kwh) : this._((kwh * 1000).round());

  static const zero = Kwh._(0);

  double get value => milli / 1000.0;

  Kwh operator +(Kwh other) => Kwh._(milli + other.milli);
  Kwh operator -(Kwh other) => Kwh._(milli - other.milli);
  Kwh operator *(num factor) => Kwh._((milli * factor).round());
  Kwh operator /(num divisor) => Kwh._((milli / divisor).round());

  bool operator <(Kwh other) => milli < other.milli;
  bool operator <=(Kwh other) => milli <= other.milli;
  bool operator >(Kwh other) => milli > other.milli;
  bool operator >=(Kwh other) => milli >= other.milli;

  bool get isNegative => milli < 0;
  bool get isZero => milli == 0;
  Kwh get abs => Kwh._(milli.abs());

  /// The number alone, without the unit.
  ///
  /// The unit belongs in the sans face: a monospace "kWh" sits on three
  /// tabular advance widths and opens a gap that reads as a typo. Callers
  /// that render a figure pair this with [unit] in `caption` style.
  String formatValue() {
    final deci = (milli / 100).round();
    final whole = deci ~/ 10;
    final fraction = (deci % 10).abs();
    return '$whole.$fraction';
  }

  static const String unit = 'kWh';

  /// Always one decimal place, per the copy guidelines.
  ///
  /// Rounds in integer space rather than via [double.toStringAsFixed], which
  /// would reintroduce exactly the float rounding this type exists to avoid
  /// (42.05 is stored as 42.0499..., and formats as "42.0").
  String format() {
    final deci = (milli / 100).round();
    final whole = deci ~/ 10;
    final fraction = (deci % 10).abs();
    return '$whole.$fraction kWh';
  }
}

/// Money, held as kobo (naira x 100).
extension type const Naira._(int kobo) implements Object {
  const Naira.fromKobo(int kobo) : this._(kobo);
  Naira.fromNaira(num naira) : this._((naira * 100).round());

  static const zero = Naira._(0);

  double get value => kobo / 100.0;

  Naira operator +(Naira other) => Naira._(kobo + other.kobo);
  Naira operator -(Naira other) => Naira._(kobo - other.kobo);
  Naira operator *(num factor) => Naira._((kobo * factor).round());

  bool operator <(Naira other) => kobo < other.kobo;
  bool operator >(Naira other) => kobo > other.kobo;
  bool get isZero => kobo == 0;

  /// A thin space (U+2009) after the naira sign.
  ///
  /// ₦ is drawn as an N with two full-width crossbars, and those bars run
  /// into the first digit — at caption sizes "₦209" reads as struck through,
  /// which on a bill is exactly the wrong impression. A hair of space clears
  /// the bars without looking like a gap. Verified on device at 12, 16, 20
  /// and 28sp.
  static const String naira = '₦\u202F';

  /// Naira with thousands separators, no kobo. Kobo are noise at the
  /// magnitudes this product deals in.
  String format() {
    final whole = (kobo / 100).round();
    final digits = whole.abs().toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return '${whole < 0 ? '-' : ''}$naira$buffer';
  }

  /// The same amount with nothing at all between the sign and the figure.
  ///
  /// For the PDF, and only the PDF. The narrow no-break space that keeps the
  /// sign's crossbars off the first digit on screen is still *Unicode
  /// whitespace*, and the PDF layer breaks lines on any of it — so a wrapped
  /// bullet in a dispute pack printed "the Band D rate is ₦" at the end of one
  /// line and "52,204." at the start of the next. Non-breaking to Flutter is
  /// not non-breaking to every renderer, and the amount in dispute is the last
  /// figure in the document that should be split in half.
  ///
  /// Closing the gap removes the break opportunity outright. At the 10pt the
  /// pack sets, Inter's naira glyph clears the digits without help, and a
  /// closed-up amount is how the figure is written in a Nigerian document
  /// anyway.
  String formatTight() => format().replaceAll(naira, '₦');
}

/// A tariff rate in kobo per kWh.
extension type const Rate._(int koboPerKwh) implements Object {
  const Rate.fromKobo(int koboPerKwh) : this._(koboPerKwh);
  Rate.fromNaira(num nairaPerKwh) : this._((nairaPerKwh * 100).round());

  double get value => koboPerKwh / 100.0;

  Naira costOf(Kwh energy) =>
      Naira.fromKobo((koboPerKwh * energy.milli / 1000).round());

  Kwh energyFor(Naira amount) => koboPerKwh == 0
      ? Kwh.zero
      : Kwh.fromMilli((amount.kobo * 1000 / koboPerKwh).round());

  String format() => '${Naira.naira}${value.toStringAsFixed(2)}/kWh';
}
