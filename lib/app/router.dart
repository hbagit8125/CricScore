import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_providers.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/home/home_screen.dart';
import '../features/match_setup/new_match_screen.dart';
import '../features/scoring/scoring_screen.dart';

/// Route paths, kept in one place so screens never hard-code strings.
abstract final class Routes {
  static const starting = '/starting';
  static const signIn = '/sign-in';
  static const home = '/';
  static const newMatch = '/match/new';
  static const matchPattern = '/match/:id';

  static String match(String id) => '/match/$id';
}

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run the redirect whenever sign-in state changes.
  final authChanged = ValueNotifier<int>(0);
  ref.listen(authStateProvider, (_, _) => authChanged.value++);

  final router = GoRouter(
    initialLocation: Routes.home,
    refreshListenable: authChanged,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      final at = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) {
        return at == Routes.starting ? null : Routes.starting;
      }
      final signedIn = auth.value != null;
      if (!signedIn) return at == Routes.signIn ? null : Routes.signIn;
      if (at == Routes.signIn || at == Routes.starting) return Routes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: Routes.starting,
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: Routes.signIn,
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.newMatch,
        builder: (context, state) => const NewMatchScreen(),
      ),
      GoRoute(
        path: Routes.matchPattern,
        builder: (context, state) =>
            ScoringScreen(matchId: state.pathParameters['id']!),
      ),
    ],
  );
  ref.onDispose(() {
    router.dispose();
    authChanged.dispose();
  });
  return router;
});
