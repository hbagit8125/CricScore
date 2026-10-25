import 'package:cricket_engine/cricket_engine.dart';
import 'package:drift/drift.dart';

import 'local/app_database.dart';

/// Saved teams and players, reused when setting up matches.
class TeamRepository {
  TeamRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AppDatabase _db;
  final DateTime Function() _clock;

  /// Saves [team] and its players in batting order, replacing any earlier
  /// version with the same id.
  Future<void> save(TeamSheet team) {
    return _db.transaction(() async {
      await _db
          .into(_db.teams)
          .insertOnConflictUpdate(
            TeamsCompanion.insert(
              id: team.id,
              name: team.name,
              updatedAt: _clock(),
            ),
          );
      await (_db.delete(
        _db.players,
      )..where((p) => p.teamId.equals(team.id))).go();
      await _db.batch((b) {
        b.insertAll(_db.players, [
          for (var i = 0; i < team.squad.length; i++)
            PlayersCompanion.insert(
              id: team.squad.elementAt(i).id,
              teamId: team.id,
              name: team.squad.elementAt(i).name,
              position: i,
            ),
        ]);
      });
    });
  }

  /// Most recently used first. Players come back in batting order as one
  /// list; the caller decides who plays.
  Stream<List<({String id, String name, List<PlayerRef> players})>> watchAll() {
    final query = _db.select(_db.teams)
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    return query.watch().asyncMap((teams) async {
      final players = await (_db.select(
        _db.players,
      )..orderBy([(p) => OrderingTerm.asc(p.position)])).get();
      return [
        for (final t in teams)
          (
            id: t.id,
            name: t.name,
            players: [
              for (final p in players)
                if (p.teamId == t.id) PlayerRef(id: p.id, name: p.name),
            ],
          ),
      ];
    });
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.teams)..where((t) => t.id.equals(id))).go();
}
