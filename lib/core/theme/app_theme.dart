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

  static ThemeData outdoor() => _build(AppColors.outdoor, Brightness.light);

  static ThemeData _build(AppColors c, Brightness brightness) {
    // Material components that are not glass (menus, dialogs, pickers) get
    // a solid colour close to the sheet glass.
    final solid = Color.alphaBlend(c.sheet, c.background);
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.runs,
      onPrimary: c.onSemantic,
      secondary: c.extras,
      onSecondary: c.onSemantic,
      error: c.wicket,
      onError: c.onSemantic,
      surface: solid,
      onSurface: c.foreground,
      onSurfaceVariant: c.muted,
      outline: c.glassBorder,
      outlineVariant: c.line,
      surfaceContainerHighest: c.key,
      surfaceContainerHigh: solid,
      surfaceContainer: solid,
      surfaceContainerLow: solid,
      // Selected chips and segments use the runs green; amber is kept for
      // extras only.
      secondaryContainer: c.runs,
      onSecondaryContainer: c.onSemantic,
    );
    final rounded14 = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
    );
    final glassSide = BorderSide(color: c.glassBorder);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: AppFonts.body,
      scaffoldBackgroundColor: c.background,
      canvasColor: solid,
      splashFactory: InkSparkle.splashFactory,
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
            headlineSmall: base.textTheme.headlineSmall?.copyWith(
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
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: c.foreground,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontFamily: AppFonts.display,
          fontWeight: FontWeight.w700,
          fontSize: 22,
          color: c.foreground,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.runs,
          foregroundColor: c.onSemantic,
          minimumSize: const Size.fromHeight(56),
          // A soft glow under the main action.
          elevation: c.isGlass ? 3 : 0,
          shadowColor: c.runs.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: const TextStyle(
            fontFamily: AppFonts.display,
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.foreground,
          backgroundColor: c.key,
          side: glassSide,
          shape: rounded14,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.key,
        labelStyle: TextStyle(color: c.muted),
        hintStyle: TextStyle(color: c.muted.withValues(alpha: 0.7)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: glassSide,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: glassSide,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c.runs, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.key,
        selectedColor: c.runs,
        side: glassSide,
        shape: const StadiumBorder(),
        labelStyle: TextStyle(
          fontFamily: AppFonts.body,
          color: c.foreground,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: TextStyle(
          fontFamily: AppFonts.body,
          color: c.onSemantic,
          fontWeight: FontWeight.w700,
        ),
        checkmarkColor: c.onSemantic,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.runs : c.key,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) =>
                s.contains(WidgetState.selected) ? c.onSemantic : c.foreground,
          ),
          side: WidgetStatePropertyAll(glassSide),
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600),
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.foreground,
        unselectedLabelColor: c.muted,
        dividerColor: c.line,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: c.key,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.glassBorder),
        ),
        labelStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelStyle: const TextStyle(
          fontFamily: AppFonts.body,
          fontWeight: FontWeight.w600,
        ),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: solid,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: glassSide,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: solid,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: glassSide,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: solid,
        contentTextStyle: TextStyle(color: c.foreground),
        actionTextColor: c.runs,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: glassSide,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.runs : c.key,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onSemantic : c.muted,
        ),
        trackOutlineColor: WidgetStatePropertyAll(c.glassBorder),
      ),
      listTileTheme: const ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
      ),
      dividerTheme: DividerThemeData(color: c.line),
    );
  }
}
