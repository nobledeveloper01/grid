import 'package:flutter/material.dart';

import 'tokens.dart';
import 'typography.dart';

/// Grid uses a single custom design language on both platforms, not Material
/// on Android and Cupertino on iOS. The product is a measurement and evidence
/// tool with a strong identity, most surfaces are custom-painted anyway, and
/// maintaining two visual systems doubles design and QA cost for no user
/// benefit in this category.
///
/// Platform *conventions* are still respected where they carry real user
/// expectation: back-swipe on iOS, system back on Android, platform share
/// sheets, platform date pickers, platform haptics.
///
/// See docs/03-TECHNICAL-DESIGN.md §6.6.
abstract final class GridTheme {
  static ThemeData light() => _build(GridColors.light, Brightness.light);
  static ThemeData dark() => _build(GridColors.dark, Brightness.dark);

  static ThemeData _build(GridColors c, Brightness brightness) {
    final type = GridTypography.of(c.textPrimary);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: c.surface,
      canvasColor: c.surface,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: brightness == Brightness.light
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF06120C),
        secondary: c.accent,
        onSecondary: c.surface,
        error: c.danger,
        onError: const Color(0xFFFFFFFF),
        surface: c.surface,
        onSurface: c.textPrimary,
        surfaceContainerHighest: c.surfaceDim,
        outline: c.outline,
      ),
      extensions: <ThemeExtension<dynamic>>[c, type],
      textTheme: TextTheme(
        displayLarge: type.display,
        headlineLarge: type.headline,
        titleLarge: type.title,
        bodyLarge: type.body,
        bodyMedium: type.body,
        labelLarge: type.label,
        bodySmall: type.caption,
      ),
      dividerTheme: DividerThemeData(color: c.outline, thickness: 1, space: 1),
      // Cards are delineated by outline and surfaceDim, not shadow. Flat
      // surfaces render faster on low-end GPUs — which is the second reason.
      cardTheme: CardThemeData(
        color: c.surfaceDim,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          minimumSize: const Size.fromHeight(Targets.outdoor),
          shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
          textStyle: type.bodyStrong,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.textPrimary,
          side: BorderSide(color: c.outline),
          minimumSize: const Size.fromHeight(Targets.min),
          shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
          textStyle: type.bodyStrong,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(Targets.min, Targets.min),
          textStyle: type.bodyStrong,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surfaceDim,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.lg,
        ),
        border: const OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide(color: c.outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: Radii.smAll,
          borderSide: BorderSide(color: c.accent, width: 2),
        ),
        labelStyle: type.label.copyWith(color: c.textSecondary),
        hintStyle: type.body.copyWith(color: c.textTertiary),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: type.title,
        iconTheme: IconThemeData(color: c.textPrimary),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radii.lg),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.surfaceInverse,
        contentTextStyle: type.body.copyWith(color: c.surface),
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: Radii.mdAll),
      ),
    );
  }
}

/// Convenient token access from a BuildContext.
extension GridThemeContext on BuildContext {
  GridColors get colors => Theme.of(this).extension<GridColors>()!;
  GridTypography get type => Theme.of(this).extension<GridTypography>()!;
}
