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
    return '${whole < 0 ? '-' : ''}₦$buffer';
  }
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

  String format() => '₦${value.toStringAsFixed(2)}/kWh';
}
