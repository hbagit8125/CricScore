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

@DriftDatabase(tables: [Matches, MatchEvents, Teams, Players])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _open());

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  static QueryExecutor _open() => driftDatabase(
    name: 'cricscore',
    web: DriftWebOptions(
      sqlite3Wasm: Uri.parse('sqlite3.wasm'),
      driftWorker: Uri.parse('drift_worker.js'),
    ),
  );
}
