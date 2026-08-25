import 'package:flutter/material.dart';

/// Design tokens for Grid.
///
/// The palette is built around one idea: electricity has states, and states
/// have colours. Available, unavailable, unknown. Everything else is neutral
/// so those three read instantly.
///
/// See docs/04-UX-DESIGN.md §2.
@immutable
class GridColors extends ThemeExtension<GridColors> {
  const GridColors({
    required this.surface,
    required this.surfaceDim,
    required this.surfaceInverse,
    required this.outline,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentSoft,
    required this.supplyOn,
    required this.supplyOff,
    required this.supplyUnknown,
    required this.warning,
    required this.danger,
    required this.estimate,
  });

  final Color surface;
  final Color surfaceDim;
  final Color surfaceInverse;
  final Color outline;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color accent;
  final Color accentSoft;

  /// Power available.
  final Color supplyOn;

  /// Power unavailable.
  ///
  /// Deliberately offset in *lightness* from [supplyOn], not only in hue.
  /// Green and red at matching luminance are indistinguishable in greyscale
  /// and to a red-green colour-blind viewer — so the two states separate on
  /// a second axis as well. Colour is still never the sole carrier of
  /// meaning: the supply strip also encodes hours as bar height and every
  /// bar carries a semantic label.
  final Color supplyOff;

  /// No data. Deliberately flat and low-salience — missing data is normal
  /// and must not read as an error.
  final Color supplyUnknown;

  final Color warning;
  final Color danger;

  /// Modelled or interpolated values. Never used for a measurement.
  final Color estimate;

  static const light = GridColors(
    surface: Color(0xFFFFFFFF),
    surfaceDim: Color(0xFFF4F5F7),
    surfaceInverse: Color(0xFF101418),
    outline: Color(0xFFD7DBE0),
    textPrimary: Color(0xFF101418),
    textSecondary: Color(0xFF5A626B),
    textTertiary: Color(0xFF8B939C),
    accent: Color(0xFF0B7A4B),
    accentSoft: Color(0xFFE4F3EB),
    supplyOn: Color(0xFF0B7A4B),
    supplyOff: Color(0xFF7E1A13),
    supplyUnknown: Color(0xFFB6BCC3),
    warning: Color(0xFFB4690E),
    danger: Color(0xFFC2352B),
    estimate: Color(0xFF7A6BC4),
  );

  /// Dark is authored, not a dimmed light theme. Users read meters at night.
  static const dark = GridColors(
    surface: Color(0xFF0E1114),
    surfaceDim: Color(0xFF181D22),
    surfaceInverse: Color(0xFFF4F5F7),
    outline: Color(0xFF2A3138),
    textPrimary: Color(0xFFEDEFF2),
    textSecondary: Color(0xFFA2AAB3),
    textTertiary: Color(0xFF6D767F),
    accent: Color(0xFF3FBF83),
    accentSoft: Color(0xFF122A20),
    supplyOn: Color(0xFF3FBF83),
    supplyOff: Color(0xFFC4544A),
    supplyUnknown: Color(0xFF3A424A),
    warning: Color(0xFFE0A44A),
    danger: Color(0xFFE8695E),
    estimate: Color(0xFF9E90DE),
  );

  @override
  GridColors copyWith({
    Color? surface,
    Color? surfaceDim,
    Color? surfaceInverse,
    Color? outline,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentSoft,
    Color? supplyOn,
    Color? supplyOff,
    Color? supplyUnknown,
    Color? warning,
    Color? danger,
    Color? estimate,
  }) {
    return GridColors(
      surface: surface ?? this.surface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      surfaceInverse: surfaceInverse ?? this.surfaceInverse,
      outline: outline ?? this.outline,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      supplyOn: supplyOn ?? this.supplyOn,
      supplyOff: supplyOff ?? this.supplyOff,
      supplyUnknown: supplyUnknown ?? this.supplyUnknown,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      estimate: estimate ?? this.estimate,
    );
  }

  @override
  GridColors lerp(ThemeExtension<GridColors>? other, double t) {
    if (other is! GridColors) return this;
    return GridColors(
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceDim: Color.lerp(surfaceDim, other.surfaceDim, t)!,
      surfaceInverse: Color.lerp(surfaceInverse, other.surfaceInverse, t)!,
      outline: Color.lerp(outline, other.outline, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
      supplyOn: Color.lerp(supplyOn, other.supplyOn, t)!,
      supplyOff: Color.lerp(supplyOff, other.supplyOff, t)!,
      supplyUnknown: Color.lerp(supplyUnknown, other.supplyUnknown, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      estimate: Color.lerp(estimate, other.estimate, t)!,
    );
  }
}

/// 4dp base spacing scale.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
}

abstract final class Radii {
  static const Radius sm = Radius.circular(8);
  static const Radius md = Radius.circular(12);
  static const Radius lg = Radius.circular(20);

  static const BorderRadius smAll = BorderRadius.all(sm);
  static const BorderRadius mdAll = BorderRadius.all(md);
  static const BorderRadius lgAll = BorderRadius.all(lg);
}

/// Minimum touch targets.
///
/// 48dp everywhere; 64dp on any control used outdoors at a meter, where the
/// user may be one-handed, in the dark, and in a hurry.
abstract final class Targets {
  static const double min = 48;
  static const double outdoor = 64;
  static const double capture = 80;
}

/// Responsive breakpoints. Layout is a function of available width only —
/// never of Platform.isIOS. A foldable gets the tablet layout when unfolded.
abstract final class Breakpoints {
  static const double medium = 600;
  static const double expanded = 1024;

  static bool isCompact(double width) => width < medium;
  static bool isMedium(double width) => width >= medium && width < expanded;
  static bool isExpanded(double width) => width >= expanded;
}

/// Motion durations. Fast and functional — animation costs frames on the
/// reference low-end device.
abstract final class Motion {
  static const Duration page = Duration(milliseconds: 220);
  static const Duration sheet = Duration(milliseconds: 260);
  static const Duration counter = Duration(milliseconds: 400);
  static const Duration chart = Duration(milliseconds: 300);
  static const Duration shutter = Duration(milliseconds: 120);
  static const Duration warning = Duration(milliseconds: 180);

  /// The first-value moment after onboarding. This is the product's promise
  /// and it earns the extra time.
  static const Duration firstValue = Duration(milliseconds: 600);
}
