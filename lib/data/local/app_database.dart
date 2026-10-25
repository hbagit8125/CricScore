import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

/// One row per match. The full state is rebuilt from [MatchEvents]; the
/// summary columns exist so lists can be shown without replaying.
@DataClassName('MatchRow')
class Matches extends Table {
  TextColumn get id => text()();

  /// `MatchJson.setupToJson`, encoded.
  TextColumn get setupJson => text()();

  /// e.g. "Lions v Tigers"
  TextColumn get title => text()();

  /// Rules name, e.g. "T20".
  TextColumn get format => text()();
  TextColumn get status => textEnum<MatchStatus>()();

  /// Result or current score, ready to show in a list.
  TextColumn get summary => text().withDefault(const Constant(''))();
  IntColumn get eventCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  /// Account the match belongs to. Null for matches saved before sign-in
  /// existed; they are claimed by the first account to sign in.
  TextColumn get ownerUid => text().nullable()();

  /// Leading events known to be in the cloud, unchanged since upload.
  IntColumn get syncedEventCount => integer().withDefault(const Constant(0))();

  /// Events stored in the cloud, so a shorter log can remove the rest.
  IntColumn get remoteEventCount => integer().withDefault(const Constant(0))();

  /// Match details changed since the last upload.
  BoolColumn get needsUpload => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

enum MatchStatus { inProgress, complete }

/// The event log of each match, in order. Append-only except for undo and
/// edits, which rewrite the tail.
@DataClassName('StoredEvent')
class MatchEvents extends Table {
  TextColumn get matchId =>
      text().references(Matches, #id, onDelete: KeyAction.cascade)();
  IntColumn get seq => integer()();

  /// `MatchJson.eventToJson`, encoded.
  TextColumn get json => text()();

  @override
  Set<Column<Object>> get primaryKey => {matchId, seq};
}

/// Saved teams, offered when setting up the next match.
@DataClassName('TeamRow')
class Teams extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get updatedAt => dateTime()();
  TextColumn get ownerUid => text().nullable()();
  BoolColumn get needsUpload => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('PlayerRow')
class Players extends Table {
  TextColumn get id => text()();
  TextColumn get teamId =>
      text().references(Teams, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text()();

  /// Usual batting order, from 0.
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Small values kept on this device, such as its id.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [Matches, MatchEvents, Teams, Players, Settings])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(matches, matches.ownerUid);
        await m.addColumn(matches, matches.syncedEventCount);
        await m.addColumn(matches, matches.remoteEventCount);
        await m.addColumn(matches, matches.needsUpload);
        await m.addColumn(teams, teams.ownerUid);
        await m.addColumn(teams, teams.needsUpload);
        await m.createTable(settings);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<String?> setting(String key) async => (await (select(
    settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String value) => into(
    settings,
  ).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  /// Matches deleted here that still need deleting from the cloud.
  Future<List<String>> pendingDeletions() async {
    final raw = await setting('pendingDeletions');
    return raw == null || raw.isEmpty ? [] : raw.split(',');
  }

  Future<void> addPendingDeletion(String id) async {
    final ids = {...await pendingDeletions(), id};
    await setSetting('pendingDeletions', ids.join(','));
  }

  Future<void> clearPendingDeletion(String id) async {
    final ids = (await pendingDeletions())..remove(id);
    await setSetting('pendingDeletions', ids.join(','));
  }

  /// Gives matches and teams saved before accounts existed to [uid].
  Future<void> claimUnowned(String uid) => transaction(() async {
    await (update(matches)..where((m) => m.ownerUid.isNull())).write(
      MatchesCompanion(ownerUid: Value(uid)),
    );
    await (update(teams)..where((t) => t.ownerUid.isNull())).write(
      TeamsCompanion(ownerUid: Value(uid)),
    );
  });

  static QueryExecutor _open() => driftDatabase(
    name: 'cricscore',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
