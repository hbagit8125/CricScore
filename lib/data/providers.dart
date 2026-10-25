import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_providers.dart';
import 'local/app_database.dart';
import 'match_repository.dart';
import 'team_repository.dart';

/// The device database. Tests override this with an in-memory one.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// Matches of the signed-in account.
final matchRepositoryProvider = Provider<MatchRepository>(
  (ref) => MatchRepository(
    ref.watch(databaseProvider),
    ownerUid: ref.watch(currentUidProvider),
  ),
);

/// Teams of the signed-in account.
final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => TeamRepository(
    ref.watch(databaseProvider),
    ownerUid: ref.watch(currentUidProvider),
  ),
);

/// Saved matches, most recent first.
final matchListProvider = StreamProvider<List<MatchSummary>>(
  (ref) => ref.watch(matchRepositoryProvider).watchAll(),
);

/// One match being scored. Every change is saved before it is shown, so
/// what the scorer sees is always what is stored.
class MatchController extends AsyncNotifier<Match> {
  MatchController(this.matchId);

  final String matchId;
  Future<void> _queue = Future.value();

  MatchRepository get _repo => ref.read(matchRepositoryProvider);

  @override
  Future<Match> build() => _repo.load(matchId);

  /// Records [event]. Throws [IllegalEventException], leaving the match
  /// unchanged, when the event breaks the rules.
  Future<void> apply(MatchEvent event) => _serial(() async {
    final before = await future;
    final after = before.apply(event);
    await _repo.append(matchId, before, after);
    state = AsyncData(after);
  });

  Future<void> undo() => _serial(() async {
    final before = await future;
    if (!before.canUndo) return;
    final after = before.undo();
    await _repo.rewrite(matchId, after);
    state = AsyncData(after);
  });

  /// Replaces the event at [index], for correcting an earlier ball.
  Future<void> replaceAt(int index, MatchEvent event) => _serial(() async {
    final before = await future;
    final after = before.replaceAt(index, event);
    await _repo.rewrite(matchId, after);
    state = AsyncData(after);
  });

  /// Runs changes one at a time so taps in quick succession are stored in
  /// order.
  Future<void> _serial(Future<void> Function() change) {
    final next = _queue.then((_) => change());
    _queue = next.catchError((Object _) {});
    return next;
  }
}

final matchControllerProvider =
    AsyncNotifierProvider.family<MatchController, Match, String>(
      MatchController.new,
    );
