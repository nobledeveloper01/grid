import 'package:flutter/material.dart';

/// Type scale for Grid.
///
/// Inter for UI. Monospace with tabular figures for meter readings and any
/// figure in an evidence context — a column of readings must align so the
/// user can compare the screen against a physical meter face.
///
/// See docs/04-UX-DESIGN.md §3.
@immutable
class GridTypography extends ThemeExtension<GridTypography> {
  const GridTypography({
    required this.display,
    required this.headline,
    required this.title,
    required this.body,
    required this.bodyStrong,
    required this.label,
    required this.caption,
    required this.meter,
    required this.figure,
  });

  /// The one number that matters on a screen.
  final TextStyle display;
  final TextStyle headline;
  final TextStyle title;
  final TextStyle body;
  final TextStyle bodyStrong;
  final TextStyle label;
  final TextStyle caption;

  /// Meter readings. Monospace, tabular.
  final TextStyle meter;

  /// Table figures and statement arithmetic. Monospace, tabular.
  final TextStyle figure;

  static const _sans = 'Inter';
  static const _mono = 'RobotoMono';

  /// Tabular figures so digits align in a column.
  static const _tabular = <FontFeature>[FontFeature.tabularFigures()];

  /// Inter and Roboto Mono ship as *variable* fonts. Flutter renders a
  /// variable font at its default instance unless the axis is named
  /// explicitly, so `fontWeight` alone silently does nothing — every weight
  /// comes out looking the same. `fontVariations` drives the `wght` axis
  /// directly; `fontWeight` is kept alongside it so the value is still right
  /// if a static instance is ever substituted.
  static List<FontVariation> _wght(double weight) =>
      [FontVariation('wght', weight)];

  static GridTypography of(Color primary) => GridTypography(
        display: TextStyle(
          fontFamily: _sans,
          fontSize: 30,
          height: 36 / 30,
          fontWeight: FontWeight.w600,
          fontVariations: _wght(600),
          color: primary,
        ),
        headline: TextStyle(
          fontFamily: _sans,
          fontSize: 22,
          height: 28 / 22,
          fontWeight: FontWeight.w600,
          fontVariations: _wght(600),
          color: primary,
        ),
        title: TextStyle(
          fontFamily: _sans,
          fontSize: 17,
          height: 23 / 17,
          fontWeight: FontWeight.w600,
          fontVariations: _wght(600),
          color: primary,
        ),
        body: TextStyle(
          fontFamily: _sans,
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w400,
          fontVariations: _wght(400),
          color: primary,
        ),
        bodyStrong: TextStyle(
          fontFamily: _sans,
          fontSize: 15,
          height: 22 / 15,
          fontWeight: FontWeight.w600,
          fontVariations: _wght(600),
          color: primary,
        ),
        label: TextStyle(
          fontFamily: _sans,
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w500,
          fontVariations: _wght(500),
          color: primary,
        ),
        caption: TextStyle(
          fontFamily: _sans,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w400,
          fontVariations: _wght(400),
          color: primary,
        ),
        meter: TextStyle(
          fontFamily: _mono,
          fontSize: 26,
          height: 30 / 26,
          fontWeight: FontWeight.w500,
          fontVariations: _wght(500),
          fontFeatures: _tabular,
          color: primary,
        ),
        figure: TextStyle(
          fontFamily: _mono,
          fontSize: 17,
          height: 23 / 17,
          fontWeight: FontWeight.w500,
          fontVariations: _wght(500),
          fontFeatures: _tabular,
          color: primary,
        ),
      );

  @override
  GridTypography copyWith({
    TextStyle? display,
    TextStyle? headline,
    TextStyle? title,
    TextStyle? body,
    TextStyle? bodyStrong,
    TextStyle? label,
    TextStyle? caption,
    TextStyle? meter,
    TextStyle? figure,
  }) {
    return GridTypography(
      display: display ?? this.display,
      headline: headline ?? this.headline,
      title: title ?? this.title,
      body: body ?? this.body,
      bodyStrong: bodyStrong ?? this.bodyStrong,
      label: label ?? this.label,
      caption: caption ?? this.caption,
      meter: meter ?? this.meter,
      figure: figure ?? this.figure,
    );
  }

  @override
  GridTypography lerp(ThemeExtension<GridTypography>? other, double t) {
    if (other is! GridTypography) return this;
    return GridTypography(
      display: TextStyle.lerp(display, other.display, t)!,
      headline: TextStyle.lerp(headline, other.headline, t)!,
      title: TextStyle.lerp(title, other.title, t)!,
      body: TextStyle.lerp(body, other.body, t)!,
      bodyStrong: TextStyle.lerp(bodyStrong, other.bodyStrong, t)!,
      label: TextStyle.lerp(label, other.label, t)!,
      caption: TextStyle.lerp(caption, other.caption, t)!,
      meter: TextStyle.lerp(meter, other.meter, t)!,
      figure: TextStyle.lerp(figure, other.figure, t)!,
    );
  }
}
