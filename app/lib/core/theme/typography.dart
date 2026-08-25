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

  static GridTypography of(Color primary) => GridTypography(
        display: TextStyle(
          fontFamily: _sans,
          fontSize: 40,
          height: 44 / 40,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        headline: TextStyle(
          fontFamily: _sans,
          fontSize: 28,
          height: 34 / 28,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        title: TextStyle(
          fontFamily: _sans,
          fontSize: 20,
          height: 26 / 20,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        body: TextStyle(
          fontFamily: _sans,
          fontSize: 16,
          height: 24 / 16,
          fontWeight: FontWeight.w400,
          color: primary,
        ),
        bodyStrong: TextStyle(
          fontFamily: _sans,
          fontSize: 16,
          height: 24 / 16,
          fontWeight: FontWeight.w600,
          color: primary,
        ),
        label: TextStyle(
          fontFamily: _sans,
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w500,
          color: primary,
        ),
        caption: TextStyle(
          fontFamily: _sans,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w400,
          color: primary,
        ),
        meter: TextStyle(
          fontFamily: _mono,
          fontSize: 32,
          height: 36 / 32,
          fontWeight: FontWeight.w500,
          fontFeatures: _tabular,
          color: primary,
        ),
        figure: TextStyle(
          fontFamily: _mono,
          fontSize: 20,
          height: 26 / 20,
          fontWeight: FontWeight.w500,
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
