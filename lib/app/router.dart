import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/home/home_screen.dart';
import '../features/match_setup/new_match_screen.dart';

/// Route paths, kept in one place so screens never hard-code strings.
abstract final class Routes {
  static const home = '/';
  static const newMatch = '/match/new';
}

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: Routes.home,
    routes: [
      GoRoute(
        path: Routes.home,
        builder: (context, state) => const HomeScreen(),
      ),
      GoRoute(
        path: Routes.newMatch,
        builder: (context, state) => const NewMatchScreen(),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
