import 'package:flutter/material.dart';

/// Colour tokens for both themes, taken from the rebuild plan mockups.
///
/// Semantic colours (runs, wicket, extras) are separate from the brand
/// accent so they keep their meaning in every theme.
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
  });

  /// Dark pitch-green scoring surface; the default look.
  static const dark = AppColors(
    background: Color(0xFF0E1A13),
    surface: Color(0xFF17271D),
    key: Color(0xFF22362A),
    foreground: Color(0xFFEEF4EE),
    muted: Color(0xFF93A99A),
    line: Color(0xFF2A4033),
    runs: Color(0xFF3CCF74),
    wicket: Color(0xFFEF5A4C),
    extras: Color(0xFFF3B54A),
    onSemantic: Color(0xFF0E1A13),
  );

  static const light = AppColors(
    background: Color(0xFFF4F7F3),
    surface: Color(0xFFFFFFFF),
    key: Color(0xFFE6EDE7),
    foreground: Color(0xFF14201A),
    muted: Color(0xFF5B6E61),
    line: Color(0xFFD3DDD5),
    runs: Color(0xFF1F8A4C),
    wicket: Color(0xFFC8382C),
    extras: Color(0xFFA86A00),
    onSemantic: Color(0xFFFFFFFF),
  );

  final Color background;
  final Color surface;

  /// Fill for keypad keys and chips.
  final Color key;
  final Color foreground;
  final Color muted;
  final Color line;
  final Color runs;
  final Color wicket;
  final Color extras;

  /// Text drawn on top of [runs], [wicket] or [extras].
  final Color onSemantic;

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
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      key: Color.lerp(key, other.key, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      line: Color.lerp(line, other.line, t)!,
      runs: Color.lerp(runs, other.runs, t)!,
      wicket: Color.lerp(wicket, other.wicket, t)!,
      extras: Color.lerp(extras, other.extras, t)!,
      onSemantic: Color.lerp(onSemantic, other.onSemantic, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get colors => Theme.of(this).extension<AppColors>()!;
}
