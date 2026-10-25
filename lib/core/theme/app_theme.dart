import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Font families bundled in assets/fonts (SIL Open Font License).
abstract final class AppFonts {
  /// Body and UI text.
  static const body = 'Barlow';

  /// Scores, numerals and headings.
  static const display = 'BarlowCondensed';
}

abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light, Brightness.light);

  static ThemeData dark() => _build(AppColors.dark, Brightness.dark);

  static ThemeData _build(AppColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.runs,
      onPrimary: c.onSemantic,
      secondary: c.extras,
      onSecondary: c.onSemantic,
      error: c.wicket,
      onError: c.onSemantic,
      surface: c.surface,
      onSurface: c.foreground,
      onSurfaceVariant: c.muted,
      outline: c.line,
      surfaceContainerHighest: c.key,
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppFonts.body,
      scaffoldBackgroundColor: c.background,
      extensions: [c],
    );

    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            displayLarge: base.textTheme.displayLarge?.copyWith(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            headlineMedium: base.textTheme.headlineMedium?.copyWith(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w700,
            ),
            titleLarge: base.textTheme.titleLarge?.copyWith(
              fontFamily: AppFonts.display,
              fontWeight: FontWeight.w600,
            ),
          )
          .apply(bodyColor: c.foreground, displayColor: c.foreground),
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.foreground,
        elevation: 0,
        centerTitle: false,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.runs,
          foregroundColor: c.onSemantic,
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
