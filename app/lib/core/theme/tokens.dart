import 'package:flutter/material.dart';

/// Design tokens for Grid.
///
/// **Amber is the brand, and that is a semantic choice as much as an
/// aesthetic one.** This is a product about electricity: current, warmth,
/// sunlight, the moment the light comes back on. A cool corporate blue or a
/// clinical grey says "utility bill". Amber says "power", and it is the
/// colour of the thing the user is actually trying to get more of.
///
/// The palette is warm throughout — the neutrals are warm greys, not blue
/// ones — so the whole app reads as lit rather than as administrative.
///
/// Three constraints hold regardless of how vivid it gets, and each is
/// asserted by a test rather than trusted:
///
/// 1. Body text clears **4.5:1** on every surface it sits on, in both themes.
/// 2. Supply states clear **3:1** against their surface.
/// 3. `supplyOn` and `supplyOff` separate in **lightness**, not only in hue,
///    so they survive greyscale and red-green colour blindness.
///
/// See DESIGN.md §2.
@immutable
class GridColors extends ThemeExtension<GridColors> {
  const GridColors({
    required this.surface,
    required this.surfaceDim,
    required this.surfaceRaised,
    required this.surfaceInverse,
    required this.outline,
    required this.outlineStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.brand,
    required this.brandDeep,
    required this.brandSoft,
    required this.onBrand,
    required this.gradientStart,
    required this.gradientEnd,
    required this.accent,
    required this.accentSoft,
    required this.supplyOn,
    required this.supplyOnSoft,
    required this.supplyOff,
    required this.supplyUnknown,
    required this.track,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.estimate,
    required this.estimateSoft,
    required this.info,
    required this.shadow,
  });

  // Surfaces — warm neutrals, so nothing reads as administrative grey.
  final Color surface;
  final Color surfaceDim;

  /// Cards that should lift off the page. Paired with [shadow].
  final Color surfaceRaised;
  final Color surfaceInverse;

  final Color outline;

  /// For borders that must be seen — focused fields, selected cards.
  final Color outlineStrong;

  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // Brand — energy amber.
  /// Fills, gradients and large elements. Pair with [onBrand], never with
  /// white: amber is too light to carry white text at 4.5:1.
  final Color brand;

  /// The text-safe amber. Use wherever brand colour must be legible *as
  /// text* on a light surface.
  final Color brandDeep;

  /// Tinted background for selected states and brand-flavoured surfaces.
  final Color brandSoft;

  /// What goes on top of [brand] — a warm near-black, not white.
  final Color onBrand;

  /// The hero gradient. Sunrise, deliberately.
  final Color gradientStart;
  final Color gradientEnd;

  /// The cool counterweight, so the palette is not monotonously warm.
  final Color accent;
  final Color accentSoft;

  // Supply states.
  final Color supplyOn;
  final Color supplyOnSoft;
  final Color supplyOff;

  /// No data. Deliberately flat and low-salience — missing data is normal
  /// here and must never read as an error.
  final Color supplyUnknown;

  /// The unfilled part of a bar or meter.
  ///
  /// Distinct from [surfaceDim]: a track has to stay visible against the
  /// page, because the *height* of a bar is what carries the data when
  /// colour cannot — in greyscale, in sunlight, or for a colour-blind
  /// viewer. `surfaceDim` on a dark surface is nearly invisible and loses
  /// that second channel.
  final Color track;

  final Color warning;
  final Color warningSoft;
  final Color danger;

  /// Modelled or interpolated values. Never used for a measurement.
  final Color estimate;
  final Color estimateSoft;

  final Color info;

  /// Warm-tinted shadow. A neutral black shadow over warm surfaces reads as
  /// dirt rather than as depth.
  final Color shadow;

  static const light = GridColors(
    surface: Color(0xFFFFFFFF),
    surfaceDim: Color(0xFFF7F5F1),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceInverse: Color(0xFF16130E),
    outline: Color(0xFFE6E1D8),
    outlineStrong: Color(0xFFCFC7B9),
    textPrimary: Color(0xFF16130E),
    textSecondary: Color(0xFF565044),
    textTertiary: Color(0xFF7D7566),
    brand: Color(0xFFF59E0B),
    brandDeep: Color(0xFF9A5B00),
    brandSoft: Color(0xFFFFF3DC),
    onBrand: Color(0xFF1A1206),
    gradientStart: Color(0xFFFFB020),
    gradientEnd: Color(0xFFF06D1E),
    accent: Color(0xFF1D4ED8),
    accentSoft: Color(0xFFE6EDFD),
    supplyOn: Color(0xFF067A4E),
    supplyOnSoft: Color(0xFFDFF3E9),
    supplyOff: Color(0xFF7E1A13),
    supplyUnknown: Color(0xFFBDB6A8),
    track: Color(0xFFEDE9E1),
    warning: Color(0xFF9A5B00),
    warningSoft: Color(0xFFFFF3DC),
    danger: Color(0xFFB3261E),
    estimate: Color(0xFF6D4AC4),
    estimateSoft: Color(0xFFEFE9FC),
    info: Color(0xFF1D4ED8),
    shadow: Color(0x1A5C4A2E),
  );

  /// Dark is authored, not a dimmed light theme. Users read meters at night,
  /// and the warm near-black keeps the app feeling lit rather than switched
  /// off.
  static const dark = GridColors(
    surface: Color(0xFF12100C),
    surfaceDim: Color(0xFF1D1A14),
    surfaceRaised: Color(0xFF242019),
    surfaceInverse: Color(0xFFF7F5F1),
    outline: Color(0xFF332E25),
    outlineStrong: Color(0xFF4A4335),
    textPrimary: Color(0xFFF5F1EA),
    textSecondary: Color(0xFFB3AB9C),
    textTertiary: Color(0xFF847C6D),
    brand: Color(0xFFFFB020),
    brandDeep: Color(0xFFFFC85C),
    brandSoft: Color(0xFF2E2211),
    onBrand: Color(0xFF1A1206),
    gradientStart: Color(0xFFFFB020),
    gradientEnd: Color(0xFFE0601A),
    accent: Color(0xFF7BA5F5),
    accentSoft: Color(0xFF15203A),
    supplyOn: Color(0xFF3FCB8A),
    supplyOnSoft: Color(0xFF10291E),
    supplyOff: Color(0xFFC4544A),
    supplyUnknown: Color(0xFF3E382E),
    track: Color(0xFF2C2721),
    warning: Color(0xFFE8B057),
    warningSoft: Color(0xFF2E2211),
    danger: Color(0xFFE8695E),
    estimate: Color(0xFFA78BFA),
    estimateSoft: Color(0xFF221A38),
    info: Color(0xFF7BA5F5),
    shadow: Color(0x66000000),
  );

  @override
  GridColors copyWith({
    Color? surface,
    Color? surfaceDim,
    Color? surfaceRaised,
    Color? surfaceInverse,
    Color? outline,
    Color? outlineStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? brand,
    Color? brandDeep,
    Color? brandSoft,
    Color? onBrand,
    Color? gradientStart,
    Color? gradientEnd,
    Color? accent,
    Color? accentSoft,
    Color? supplyOn,
    Color? supplyOnSoft,
    Color? supplyOff,
    Color? supplyUnknown,
    Color? track,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? estimate,
    Color? estimateSoft,
    Color? info,
    Color? shadow,
  }) {
    return GridColors(
      surface: surface ?? this.surface,
      surfaceDim: surfaceDim ?? this.surfaceDim,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceInverse: surfaceInverse ?? this.surfaceInverse,
      outline: outline ?? this.outline,
      outlineStrong: outlineStrong ?? this.outlineStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      brand: brand ?? this.brand,
      brandDeep: brandDeep ?? this.brandDeep,
      brandSoft: brandSoft ?? this.brandSoft,
      onBrand: onBrand ?? this.onBrand,
      gradientStart: gradientStart ?? this.gradientStart,
      gradientEnd: gradientEnd ?? this.gradientEnd,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      supplyOn: supplyOn ?? this.supplyOn,
      supplyOnSoft: supplyOnSoft ?? this.supplyOnSoft,
      supplyOff: supplyOff ?? this.supplyOff,
      supplyUnknown: supplyUnknown ?? this.supplyUnknown,
      track: track ?? this.track,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      estimate: estimate ?? this.estimate,
      estimateSoft: estimateSoft ?? this.estimateSoft,
      info: info ?? this.info,
      shadow: shadow ?? this.shadow,
    );
  }

  @override
  GridColors lerp(ThemeExtension<GridColors>? other, double t) {
    if (other is! GridColors) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return GridColors(
      surface: l(surface, other.surface),
      surfaceDim: l(surfaceDim, other.surfaceDim),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceInverse: l(surfaceInverse, other.surfaceInverse),
      outline: l(outline, other.outline),
      outlineStrong: l(outlineStrong, other.outlineStrong),
      textPrimary: l(textPrimary, other.textPrimary),
      textSecondary: l(textSecondary, other.textSecondary),
      textTertiary: l(textTertiary, other.textTertiary),
      brand: l(brand, other.brand),
      brandDeep: l(brandDeep, other.brandDeep),
      brandSoft: l(brandSoft, other.brandSoft),
      onBrand: l(onBrand, other.onBrand),
      gradientStart: l(gradientStart, other.gradientStart),
      gradientEnd: l(gradientEnd, other.gradientEnd),
      accent: l(accent, other.accent),
      accentSoft: l(accentSoft, other.accentSoft),
      supplyOn: l(supplyOn, other.supplyOn),
      supplyOnSoft: l(supplyOnSoft, other.supplyOnSoft),
      supplyOff: l(supplyOff, other.supplyOff),
      supplyUnknown: l(supplyUnknown, other.supplyUnknown),
      track: l(track, other.track),
      warning: l(warning, other.warning),
      warningSoft: l(warningSoft, other.warningSoft),
      danger: l(danger, other.danger),
      estimate: l(estimate, other.estimate),
      estimateSoft: l(estimateSoft, other.estimateSoft),
      info: l(info, other.info),
      shadow: l(shadow, other.shadow),
    );
  }

  /// The hero gradient. Used on the one card per screen that carries the
  /// number the user opened the app for.
  LinearGradient get heroGradient => LinearGradient(
        colors: [gradientStart, gradientEnd],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  /// A soft wash for section backgrounds, so the page is not a flat sheet.
  LinearGradient get washGradient => LinearGradient(
        colors: [brandSoft, surface],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
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
  static const Radius sm = Radius.circular(10);
  static const Radius md = Radius.circular(16);
  static const Radius lg = Radius.circular(24);
  static const Radius xl = Radius.circular(32);

  static const BorderRadius smAll = BorderRadius.all(sm);
  static const BorderRadius mdAll = BorderRadius.all(md);
  static const BorderRadius lgAll = BorderRadius.all(lg);
  static const BorderRadius xlAll = BorderRadius.all(xl);
}

/// Minimum touch targets.
///
/// 48dp everywhere; 64dp on any control used outdoors at a meter, where the
/// user may be one-handed, in the dark, and in a hurry.
abstract final class Targets {
  /// The accessibility floor. Nothing tappable is smaller than this.
  static const double min = 48;

  /// Standard buttons and rows. Comfortable without being oversized — a
  /// full-width 64dp button reads as a landing page, not as a tool.
  static const double control = 52;

  /// Controls used *outdoors at a meter*, where the user may be
  /// one-handed, in the dark and in a hurry. Only the capture screen and
  /// the reading keypad earn this.
  static const double outdoor = 64;

  static const double capture = 76;
}

/// Responsive breakpoints. Layout is a function of available width only —
/// never of `Platform.isIOS`. A foldable gets the tablet layout when
/// unfolded, which is correct.
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
  static const Duration press = Duration(milliseconds: 120);

  /// Staggered list entrance, per item.
  static const Duration stagger = Duration(milliseconds: 40);

  /// The first-value moment after onboarding. That is the product's promise
  /// and it earns the extra time.
  static const Duration firstValue = Duration(milliseconds: 600);
}

/// Elevation, expressed as warm-tinted shadows rather than Material's
/// neutral black — a neutral shadow over warm surfaces reads as dirt.
abstract final class Shadows {
  static List<BoxShadow> card(Color shadow) => [
        BoxShadow(color: shadow, blurRadius: 16, offset: const Offset(0, 4)),
      ];

  static List<BoxShadow> raised(Color shadow) => [
        BoxShadow(color: shadow, blurRadius: 28, offset: const Offset(0, 10)),
      ];

  static List<BoxShadow> glow(Color colour) => [
        BoxShadow(
          color: colour.withValues(alpha: 0.35),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
}
