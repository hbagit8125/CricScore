import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../sync/sync_providers.dart';
import 'router.dart';

class CricScoreApp extends ConsumerWidget {
  const CricScoreApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps cloud sync running for as long as the app is.
    ref.watch(syncControllerProvider);
    return MaterialApp.router(
      title: 'CricScore',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
