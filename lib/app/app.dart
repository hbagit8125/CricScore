import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/preferences.dart';
import '../core/theme/app_theme.dart';
import '../sync/sync_providers.dart';
import 'router.dart';

class CricScoreApp extends ConsumerWidget {
  const CricScoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps cloud sync running for as long as the app is.
    ref.watch(syncControllerProvider);
    final choice =
        ref.watch(preferencesProvider).value?.theme ?? ThemeChoice.system;
    return MaterialApp.router(
      title: 'CricScore',
      debugShowCheckedModeBanner: false,
      theme: choice == ThemeChoice.outdoor
          ? AppTheme.outdoor()
          : AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: switch (choice) {
        ThemeChoice.system => ThemeMode.system,
        ThemeChoice.dark => ThemeMode.dark,
        ThemeChoice.light || ThemeChoice.outdoor => ThemeMode.light,
      },
      routerConfig: ref.watch(routerProvider),
    );
  }
}
