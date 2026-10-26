import 'package:flutter/material.dart';

/// Colour tokens for every theme.
///
/// Semantic colours (runs, wicket, extras) are separate from the glass
/// surfaces so they keep their meaning in every theme. Dark and light are
/// glass themes: see-through panels over a glowing backdrop. Outdoor is
/// solid and high contrast, because frosted glass is hard to read in sun.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.key,
    required this.foreground,
    required this.muted,
    required this.line,
    required this.runs,
    required this.wicket,
    required this.extras,
    required this.onSemantic,
    required this.glassBorder,
    required this.sheet,
    required this.blur,
    required this.backdrop,
    required this.glows,
  });

  /// Night under floodlights: deep pitch green with emerald and teal glows.
  /// The default look.
  static const dark = AppColors(
    background: Color(0xFF07130E),
    surface: Color(0x14FFFFFF),
    key: Color(0x1AFFFFFF),
    foreground: Color(0xFFF1F7F2),
    muted: Color(0xFFA3B8AA),
    line: Color(0x1FFFFFFF),
    runs: Color(0xFF3CCF74),
    wicket: Color(0xFFFF6B5C),
    extras: Color(0xFFF6BE55),
    onSemantic: Color(0xFF06120C),
    glassBorder: Color(0x2EFFFFFF),
    sheet: Color(0xD9102019),
    blur: 22,
    backdrop: [Color(0xFF0D2A1E), Color(0xFF07150F), Color(0xFF030A07)],
    glows: [Color(0x803CCF74), Color(0x5C1B8FB0), Color(0x3D1E6B4A)],
  );

  /// Morning light: mint and sky glows behind milky glass.
  static const light = AppColors(
    background: Color(0xFFEFF6F1),
    surface: Color(0x99FFFFFF),
    key: Color(0xB3FFFFFF),
    foreground: Color(0xFF10201A),
    muted: Color(0xFF4F6457),
    line: Color(0x1A10201A),
    runs: Color(0xFF1F8A4C),
    wicket: Color(0xFFC8382C),
    extras: Color(0xFFA86A00),
    onSemantic: Color(0xFFFFFFFF),
    glassBorder: Color(0xD9FFFFFF),
    sheet: Color(0xE6F7FBF8),
    blur: 22,
    backdrop: [Color(0xFFDDF1E5), Color(0xFFF1F7F3), Color(0xFFE3EEF8)],
    glows: [Color(0x803CCF74), Color(0x666FB6FF), Color(0x40F6BE55)],
  );

  /// High contrast for bright sunshine: black on white, solid panels with
  /// black edges, deeper semantic colours.
  static const outdoor = AppColors(
    background: Color(0xFFFFFFFF),
    surface: Color(0xFFF2F2F2),
    key: Color(0xFFE0E0E0),
    foreground: Color(0xFF000000),
    muted: Color(0xFF2E2E2E),
    line: Color(0xFF000000),
    runs: Color(0xFF00632A),
    wicket: Color(0xFFB00020),
    extras: Color(0xFF7A3E00),
    onSemantic: Color(0xFFFFFFFF),
    glassBorder: Color(0xFF000000),
    sheet: Color(0xFFFFFFFF),
    blur: 0,
    backdrop: [Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
    glows: [],
  );

  /// Solid fallback behind everything.
  final Color background;

  /// Glass panel tint (see-through in the glass themes).
  final Color surface;

  /// Fill for keypad keys, chips and fields.
  final Color key;
  final Color foreground;
  final Color muted;
  final Color line;
  final Color runs;
  final Color wicket;
  final Color extras;

  /// Text drawn on top of [runs], [wicket] or [extras].
  final Color onSemantic;

  /// The light edge that makes glass read as glass.
  final Color glassBorder;

  /// Bottom sheets and dialogs: glass, but opaque enough to read.
  final Color sheet;

  /// Backdrop blur behind glass; 0 for solid panels.
  final double blur;

  /// Background gradient, top to bottom.
  final List<Color> backdrop;

  /// Soft light pools painted on the background.
  final List<Color> glows;

  bool get isGlass => blur > 0;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? key,
    Color? foreground,
    Color? muted,
    Color? line,
    Color? runs,
    Color? wicket,
    Color? extras,
    Color? onSemantic,
    Color? glassBorder,
    Color? sheet,
    double? blur,
    List<Color>? backdrop,
    List<Color>? glows,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      key: key ?? this.key,
      foreground: foreground ?? this.foreground,
      muted: muted ?? this.muted,
      line: line ?? this.line,
      runs: runs ?? this.runs,
      wicket: wicket ?? this.wicket,
      extras: extras ?? this.extras,
      onSemantic: onSemantic ?? this.onSemantic,
      glassBorder: glassBorder ?? this.glassBorder,
      sheet: sheet ?? this.sheet,
      blur: blur ?? this.blur,
      backdrop: backdrop ?? this.backdrop,
      glows: glows ?? this.glows,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    final near = t < 0.5 ? this : other;
    return AppColors(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      key: c(key, other.key),
      foreground: c(foreground, other.foreground),
      muted: c(muted, other.muted),
      line: c(line, other.line),
      runs: c(runs, other.runs),
      wicket: c(wicket, other.wicket),
      extras: c(extras, other.extras),
      onSemantic: c(onSemantic, other.onSemantic),
      glassBorder: c(glassBorder, other.glassBorder),
      sheet: c(sheet, other.sheet),
      blur: blur + (other.blur - blur) * t,
      backdrop: near.backdrop,
      glows: near.glows,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
