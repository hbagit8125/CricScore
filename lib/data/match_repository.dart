import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'local/app_database.dart';

/// A saved match as shown in lists.
final class MatchSummary {
  const MatchSummary({
    required this.id,
    required this.title,
    required this.format,
    required this.status,
    required this.summary,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String format;
  final MatchStatus status;
  final String summary;
  final DateTime updatedAt;
}

/// Saves matches on the device. Every event is written as it is recorded,
/// so a match survives the app closing at any moment.
class MatchRepository {
  MatchRepository(
    this._db, {
    this.ownerUid,
    DateTime Function()? clock,
    Uuid? uuid,
  }) : _clock = clock ?? DateTime.now,
       _uuid = uuid ?? const Uuid();

  final AppDatabase _db;

  /// The signed-in account. Lists show only its matches; null shows all.
  final String? ownerUid;
  final DateTime Function() _clock;
  final Uuid _uuid;

  /// Saves a new match and returns its id.
  Future<String> create(MatchSetup setup) async {
    final match = Match.start(setup);
    final id = _uuid.v4();
    final now = _clock();
    await _db
        .into(_db.matches)
        .insert(
          MatchesCompanion.insert(
            id: id,
            setupJson: jsonEncode(MatchJson.setupToJson(setup)),
            title: '${setup.teamA.name} v ${setup.teamB.name}',
            format: setup.rules.name,
            status: MatchStatus.inProgress,
            summary: Value(_summaryOf(match)),
            createdAt: now,
            updatedAt: now,
            ownerUid: Value(ownerUid),
          ),
        );
    return id;
  }

  /// Rebuilds a saved match from its event log.
  Future<Match> load(String id) async {
    final row = await (_db.select(
      _db.matches,
    )..where((m) => m.id.equals(id))).getSingle();
    final events =
        await (_db.select(_db.matchEvents)
              ..where((e) => e.matchId.equals(id))
              ..orderBy([(e) => OrderingTerm.asc(e.seq)]))
            .get();
    return Match.replay(MatchJson.setupFromJson(_decode(row.setupJson)), [
      for (final e in events) MatchJson.eventFromJson(_decode(e.json)),
    ]);
  }

  /// Stores [after], which must be [before] plus one or more new events.
  Future<void> append(String id, Match before, Match after) {
    assert(after.events.length > before.events.length);
    return _db.transaction(() async {
      await _db.batch((b) {
        b.insertAll(_db.matchEvents, [
          for (var i = before.events.length; i < after.events.length; i++)
            MatchEventsCompanion.insert(
              matchId: id,
              seq: i,
              json: jsonEncode(MatchJson.eventToJson(after.events[i])),
            ),
        ]);
      });
      await _updateSummary(id, after);
    });
  }

  /// Replaces the whole log, for undo and edits.
  Future<void> rewrite(String id, Match match) {
    return _db.transaction(() async {
      // Events before the first change are still correct in the cloud.
      final old =
          await (_db.select(_db.matchEvents)
                ..where((e) => e.matchId.equals(id))
                ..orderBy([(e) => OrderingTerm.asc(e.seq)]))
              .get();
      var same = 0;
      while (same < old.length &&
          same < match.events.length &&
          old[same].json ==
              jsonEncode(MatchJson.eventToJson(match.events[same]))) {
        same++;
      }
      final row = await (_db.select(
        _db.matches,
      )..where((m) => m.id.equals(id))).getSingle();
      if (row.syncedEventCount > same) {
        await (_db.update(_db.matches)..where((m) => m.id.equals(id))).write(
          MatchesCompanion(syncedEventCount: Value(same)),
        );
      }
      await (_db.delete(
        _db.matchEvents,
      )..where((e) => e.matchId.equals(id))).go();
      await _db.batch((b) {
        b.insertAll(_db.matchEvents, [
          for (var i = 0; i < match.events.length; i++)
            MatchEventsCompanion.insert(
              matchId: id,
              seq: i,
              json: jsonEncode(MatchJson.eventToJson(match.events[i])),
            ),
        ]);
      });
      await _updateSummary(id, match);
    });
  }

  /// Stores a changed setup (for example a renamed player) for [match].
  Future<void> updateSetup(String id, Match match) => _db.transaction(() async {
    await (_db.update(_db.matches)..where((m) => m.id.equals(id))).write(
      MatchesCompanion(
        setupJson: Value(jsonEncode(MatchJson.setupToJson(match.setup))),
      ),
    );
    await _updateSummary(id, match);
  });

  /// Deletes the match here and, once online, from the cloud.
  Future<void> delete(String id) => _db.transaction(() async {
    final row = await (_db.select(
      _db.matches,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (row?.ownerUid != null) await _db.addPendingDeletion(id);
    await (_db.delete(_db.matches)..where((m) => m.id.equals(id))).go();
  });

  /// Most recently played first.
  Stream<List<MatchSummary>> watchAll() {
    final uid = ownerUid;
    final query = _db.select(_db.matches)
      ..where(
        (m) => uid == null ? const Constant(true) : m.ownerUid.equals(uid),
      )
      ..orderBy([(m) => OrderingTerm.desc(m.updatedAt)]);
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          MatchSummary(
            id: r.id,
            title: r.title,
            format: r.format,
            status: r.status,
            summary: r.summary,
            updatedAt: r.updatedAt,
          ),
      ],
    );
  }

  Future<void> _updateSummary(String id, Match match) {
    return (_db.update(_db.matches)..where((m) => m.id.equals(id))).write(
      MatchesCompanion(
        status: Value(
          match.state.isComplete
              ? MatchStatus.complete
              : MatchStatus.inProgress,
        ),
        summary: Value(_summaryOf(match)),
        eventCount: Value(match.events.length),
        updatedAt: Value(_clock()),
        needsUpload: const Value(true),
      ),
    );
  }

  static String _summaryOf(Match match) {
    final state = match.state;
    final result = state.result;
    if (result != null) return result.describe(match.setup);
    final inn = state.currentInnings;
    if (inn == null || (inn.legalBalls == 0 && inn.runs == 0)) {
      return state.innings.length <= 1 ? 'Not started' : 'Innings break';
    }
    final team = match.setup.team(inn.battingTeamId).name;
    return '$team ${inn.runs}/${inn.wickets} (${inn.oversText})';
  }

  static Map<String, Object?> _decode(String s) =>
      (jsonDecode(s) as Map).cast<String, Object?>();
}
