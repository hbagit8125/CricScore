import 'dart:convert';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:drift/drift.dart';

import '../data/local/app_database.dart';
import 'cloud_store.dart';

/// Cloud layout:
///
/// - `matches/{matchId}`: owner, summary, setup, event count, scoring device
/// - `matches/{matchId}/events/{seq}`: one document per event, in order
/// - `users/{uid}/teams/{teamId}`: saved teams with their players
///
/// The device database is the source of truth for whoever is scoring; the
/// cloud copy is a backup, the way to move between devices, and what live
/// viewers read.
class SyncService {
  SyncService({
    required AppDatabase db,
    required CloudStore cloud,
    required this.uid,
    required this.deviceId,
  }) : _db = db,
       _cloud = cloud;

  final AppDatabase _db;
  final CloudStore _cloud;
  final String uid;
  final String deviceId;

  /// Firestore allows 500 writes per batch; stay well under.
  static const _batchLimit = 400;

  static String seqId(int seq) => seq.toString().padLeft(6, '0');

  static String matchPath(String id) => 'matches/$id';

  static String eventsPath(String id) => 'matches/$id/events';

  String get _teamsPath => 'users/$uid/teams';

  /// Everything, in a safe order: deletions, then downloads, then uploads.
  Future<void> syncAll() async {
    await _db.claimUnowned(uid);
    await pushDeletions();
    await pull();
    await pushPending();
  }

  /// Uploads every match and team changed since the last upload.
  Future<void> pushPending() async {
    final matches = await (_db.select(
      _db.matches,
    )..where((m) => m.ownerUid.equals(uid) & m.needsUpload)).get();
    for (final m in matches) {
      await pushMatch(m.id);
    }
    await pushTeams();
  }

  /// Uploads one match: its summary, events not yet in the cloud, and
  /// removal of cloud events beyond the local log after an undo.
  Future<void> pushMatch(String id) async {
    final row = await (_db.select(
      _db.matches,
    )..where((m) => m.id.equals(id))).getSingleOrNull();
    if (row == null || row.ownerUid != uid) return;
    final events =
        await (_db.select(_db.matchEvents)
              ..where(
                (e) =>
                    e.matchId.equals(id) &
                    e.seq.isBiggerOrEqualValue(row.syncedEventCount),
              )
              ..orderBy([(e) => OrderingTerm.asc(e.seq)]))
            .get();

    final writes = <CloudWrite>[
      for (final e in events)
        CloudSet('${eventsPath(id)}/${seqId(e.seq)}', {
          'seq': e.seq,
          'e': jsonDecode(e.json),
        }),
      for (var seq = row.eventCount; seq < row.remoteEventCount; seq++)
        CloudDelete('${eventsPath(id)}/${seqId(seq)}'),
      // The summary goes last, so readers never see a count ahead of the
      // events actually stored.
      CloudSet(matchPath(id), {
        'ownerUid': uid,
        'title': row.title,
        'format': row.format,
        'status': row.status.name,
        'summary': row.summary,
        'setup': jsonDecode(row.setupJson),
        'eventCount': row.eventCount,
        'schemaVersion': engineSchemaVersion,
        'scorerDeviceId': deviceId,
        'createdAt': row.createdAt,
        'updatedAt': serverTime,
      }, merge: true),
    ];
    // Security rules check ownership on every batch, so each earlier batch
    // of a large upload also states the owner.
    final owner = CloudSet(matchPath(id), {'ownerUid': uid}, merge: true);
    for (var i = 0; i < writes.length; i += _batchLimit) {
      final chunk = writes.skip(i).take(_batchLimit).toList();
      final last = i + _batchLimit >= writes.length;
      await _cloud.commit(last ? chunk : [owner, ...chunk]);
    }

    // Mark it synced only if nothing changed while uploading.
    await (_db.update(
      _db.matches,
    )..where((m) => m.id.equals(id) & m.updatedAt.equals(row.updatedAt))).write(
      MatchesCompanion(
        syncedEventCount: Value(row.eventCount),
        remoteEventCount: Value(row.eventCount),
        needsUpload: const Value(false),
      ),
    );
  }

  /// Removes matches deleted on this device from the cloud.
  Future<void> pushDeletions() async {
    for (final id in await _db.pendingDeletions()) {
      final match = await _cloud.get(matchPath(id));
      if (match != null && match['ownerUid'] == uid) {
        final events = await _cloud.query(eventsPath(id));
        final writes = <CloudWrite>[
          for (final e in events) CloudDelete('${eventsPath(id)}/${e.id}'),
          CloudDelete(matchPath(id)),
        ];
        for (var i = 0; i < writes.length; i += _batchLimit) {
          await _cloud.commit(writes.skip(i).take(_batchLimit).toList());
        }
      }
      await _db.clearPendingDeletion(id);
    }
  }

  /// Downloads matches and teams from other devices. A match with local
  /// changes not yet uploaded is never overwritten.
  Future<void> pull() async {
    final pendingDeletes = (await _db.pendingDeletions()).toSet();
    final remote = await _cloud.query(
      'matches',
      whereField: 'ownerUid',
      isEqualTo: uid,
    );
    for (final doc in remote) {
      if (pendingDeletes.contains(doc.id)) continue;
      final data = doc.data;
      final version = data['schemaVersion'] as int? ?? 1;
      if (version > engineSchemaVersion) continue;
      // Missing while a first upload is still in progress.
      final eventCount = data['eventCount'] as int?;
      if (eventCount == null) continue;
      final local = await (_db.select(
        _db.matches,
      )..where((m) => m.id.equals(doc.id))).getSingleOrNull();
      if (local != null) {
        if (local.needsUpload) continue; // unsent changes here win
        if (local.eventCount == eventCount &&
            local.syncedEventCount == eventCount &&
            data['scorerDeviceId'] == deviceId) {
          continue; // our own upload, already up to date
        }
      }
      await _importMatch(doc.id, data, eventCount);
    }
    await _pullTeams();
  }

  Future<void> _importMatch(
    String id,
    Map<String, Object?> data,
    int eventCount,
  ) async {
    final events = await _cloud.query(
      eventsPath(id),
      orderBy: 'seq',
      limit: eventCount,
    );
    if (events.length != eventCount) return; // still uploading
    await _db.transaction(() async {
      await _db
          .into(_db.matches)
          .insertOnConflictUpdate(
            MatchesCompanion.insert(
              id: id,
              setupJson: jsonEncode(data['setup']),
              title: data['title']! as String,
              format: data['format']! as String,
              status: MatchStatus.values.byName(data['status']! as String),
              summary: Value(data['summary'] as String? ?? ''),
              eventCount: Value(eventCount),
              createdAt: data['createdAt'] as DateTime? ?? DateTime.now(),
              updatedAt: data['updatedAt'] as DateTime? ?? DateTime.now(),
              ownerUid: Value(uid),
              syncedEventCount: Value(eventCount),
              remoteEventCount: Value(eventCount),
              needsUpload: const Value(false),
            ),
          );
      await (_db.delete(
        _db.matchEvents,
      )..where((e) => e.matchId.equals(id))).go();
      await _db.batch((b) {
        b.insertAll(_db.matchEvents, [
          for (final e in events)
            MatchEventsCompanion.insert(
              matchId: id,
              seq: e.data['seq']! as int,
              json: jsonEncode(e.data['e']),
            ),
        ]);
      });
    });
  }

  /// Uploads saved teams changed on this device.
  Future<void> pushTeams() async {
    final teams = await (_db.select(
      _db.teams,
    )..where((t) => t.ownerUid.equals(uid) & t.needsUpload)).get();
    for (final t in teams) {
      final players =
          await (_db.select(_db.players)
                ..where((p) => p.teamId.equals(t.id))
                ..orderBy([(p) => OrderingTerm.asc(p.position)]))
              .get();
      await _cloud.commit([
        CloudSet('$_teamsPath/${t.id}', {
          'name': t.name,
          'players': [
            for (final p in players) {'id': p.id, 'name': p.name},
          ],
          'updatedAt': t.updatedAt,
        }),
      ]);
      await (_db.update(_db.teams)
            ..where((r) => r.id.equals(t.id) & r.updatedAt.equals(t.updatedAt)))
          .write(const TeamsCompanion(needsUpload: Value(false)));
    }
  }

  Future<void> _pullTeams() async {
    for (final doc in await _cloud.query(_teamsPath)) {
      final local = await (_db.select(
        _db.teams,
      )..where((t) => t.id.equals(doc.id))).getSingleOrNull();
      if (local != null && local.needsUpload) continue;
      final data = doc.data;
      final players = (data['players']! as List).cast<Map<String, Object?>>();
      await _db.transaction(() async {
        await _db
            .into(_db.teams)
            .insertOnConflictUpdate(
              TeamsCompanion.insert(
                id: doc.id,
                name: data['name']! as String,
                updatedAt: data['updatedAt'] as DateTime? ?? DateTime.now(),
                ownerUid: Value(uid),
                needsUpload: const Value(false),
              ),
            );
        await (_db.delete(
          _db.players,
        )..where((p) => p.teamId.equals(doc.id))).go();
        await _db.batch((b) {
          b.insertAll(_db.players, [
            for (var i = 0; i < players.length; i++)
              PlayersCompanion.insert(
                id: players[i]['id']! as String,
                teamId: doc.id,
                name: players[i]['name']! as String,
                position: i,
              ),
          ]);
        });
      });
    }
  }
}
