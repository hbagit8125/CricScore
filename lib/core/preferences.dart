import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/providers.dart';

/// How the app looks. Outdoor is a high-contrast light theme for bright
/// sunshine.
enum ThemeChoice { system, light, dark, outdoor }

/// Display preferences, kept on this device.
final class Preferences {
  const Preferences({this.theme = ThemeChoice.system, this.leftHanded = false});

  final ThemeChoice theme;

  /// Puts the wicket and undo keys on the left of the keypad.
  final bool leftHanded;

  Preferences copyWith({ThemeChoice? theme, bool? leftHanded}) => Preferences(
    theme: theme ?? this.theme,
    leftHanded: leftHanded ?? this.leftHanded,
  );
}

class PreferencesController extends AsyncNotifier<Preferences> {
  static const _themeKey = 'pref.theme';
  static const _leftHandedKey = 'pref.leftHanded';

  @override
  Future<Preferences> build() async {
    final db = ref.watch(databaseProvider);
    final theme = await db.setting(_themeKey);
    return Preferences(
      theme: ThemeChoice.values.asNameMap()[theme] ?? ThemeChoice.system,
      leftHanded: await db.setting(_leftHandedKey) == 'true',
    );
  }

  Future<void> setTheme(ThemeChoice theme) async {
    await ref.read(databaseProvider).setSetting(_themeKey, theme.name);
    state = AsyncData(_current.copyWith(theme: theme));
  }

  Future<void> setLeftHanded(bool value) async {
    await ref.read(databaseProvider).setSetting(_leftHandedKey, '$value');
    state = AsyncData(_current.copyWith(leftHanded: value));
  }

  Preferences get _current => state.value ?? const Preferences();
}

final preferencesProvider =
    AsyncNotifierProvider<PreferencesController, Preferences>(
      PreferencesController.new,
    );
