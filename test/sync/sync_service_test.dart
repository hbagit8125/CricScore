import 'package:cric_score/data/local/app_database.dart';
import 'package:cric_score/data/match_repository.dart';
import 'package:cric_score/data/team_repository.dart';
import 'package:cric_score/sync/cloud_store.dart';
import 'package:cric_score/sync/sync_service.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/memory_cloud_store.dart';

MatchSetup setup({MatchRules rules = MatchRules.t20}) {
  TeamSheet team(String id, String name, String prefix) => TeamSheet(
    id: id,
    name: name,
    players: [
      for (var i = 1; i <= 11; i++)
        PlayerRef(id: '$prefix$i', name: '$name $i'),
    ],
  );
  return MatchSetup(
    rules: rules,
    teamA: team('LIO', 'Lions', 'A'),
    teamB: team('TIG', 'Tigers', 'B'),
    toss: const Toss(wonByTeamId: 'LIO', decision: TossDecision.bat),
  );
}

/// One phone: its own database, signed in as [uid].
final class Device {
  Device(this.cloud, {this.uid = 'u1', String? deviceId})
    : db = AppDatabase(NativeDatabase.memory()) {
    sync = SyncService(
      db: db,
      cloud: cloud,
      uid: uid,
      deviceId: deviceId ?? 'device-${identityHashCode(this)}',
    );
    matches = MatchRepository(db, ownerUid: uid);
    teams = TeamRepository(db, ownerUid: uid);
  }

  final MemoryCloudStore cloud;
  final String uid;
  final AppDatabase db;
  late final SyncService sync;
  late final MatchRepository matches;
  late final TeamRepository teams;

  /// Creates a match and records [events], saving each like the app does.
  Future<(String, Match)> score(
    List<MatchEvent> events, {
    MatchRules rules = MatchRules.t20,
  }) async {
    final id = await matches.create(setup(rules: rules));
    var m = Match.start(setup(rules: rules));
    for (final e in events) {
      final next = m.apply(e);
      await matches.append(id, m, next);
      m = next;
    }
    return (id, m);
  }
}

const opening = <MatchEvent>[
  OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'),
  BowlerSelected('B11'),
  Delivery.four(),
  Delivery.runs(1),
  Delivery.wide(),
];

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late MemoryCloudStore cloud;
  final devices = <Device>[];

  Device device({String uid = 'u1', String? deviceId}) {
    final d = Device(cloud, uid: uid, deviceId: deviceId);
    devices.add(d);
    return d;
  }

  setUp(() => cloud = MemoryCloudStore());
  tearDown(() async {
    for (final d in devices) {
      await d.db.close();
    }
    devices.clear();
  });

  Future<List<int>> remoteSeqs(String id) async => [
    for (final e in await cloud.query(
      SyncService.eventsPath(id),
      orderBy: 'seq',
    ))
      e.data['seq']! as int,
  ];

  Future<Map<String, Object?>?> remoteMatch(String id) =>
      cloud.get(SyncService.matchPath(id));

  test('uploads a match, its events, and marks it synced', () async {
    final phone = device();
    final (id, _) = await phone.score(opening);
    await phone.sync.pushPending();

    final doc = (await remoteMatch(id))!;
    expect(doc['ownerUid'], 'u1');
    expect(doc['eventCount'], 5);
    expect(doc['summary'], 'Lions 6/0 (0.2)');
    expect(await remoteSeqs(id), [0, 1, 2, 3, 4]);

    final row = await phone.db.select(phone.db.matches).getSingle();
    expect(row.needsUpload, isFalse);
    expect(row.syncedEventCount, 5);
  });

  test('later balls upload only what is new', () async {
    final phone = device();
    final (id, m) = await phone.score(opening);
    await phone.sync.pushPending();
    await phone.matches.append(id, m, m.apply(const Delivery.six()));
    await phone.sync.pushPending();
    expect(await remoteSeqs(id), [0, 1, 2, 3, 4, 5]);
    final doc = (await remoteMatch(id))!;
    expect(doc['eventCount'], 6);
  });

  test('undo removes the extra event from the cloud', () async {
    final phone = device();
    final (id, m) = await phone.score(opening);
    await phone.sync.pushPending();
    await phone.matches.rewrite(id, m.undo().undo());
    await phone.sync.pushPending();
    expect(await remoteSeqs(id), [0, 1, 2]);
  });

  test('correcting an earlier ball re-uploads from that ball', () async {
    final phone = device();
    final (id, m) = await phone.score(opening);
    await phone.sync.pushPending();
    await phone.matches.rewrite(id, m.replaceAt(2, const Delivery.six()));
    final row = await phone.db.select(phone.db.matches).getSingle();
    expect(row.syncedEventCount, 2);
    await phone.sync.pushPending();
    final third = await cloud.get(
      '${SyncService.eventsPath(id)}/${SyncService.seqId(2)}',
    );
    expect(third!['e'], {'type': 'delivery', 'boundary': 6});
  });

  test('another phone signed in to the same account gets the match', () async {
    final first = device();
    final (id, m) = await first.score(opening);
    await first.sync.pushPending();

    final second = device();
    await second.sync.syncAll();
    final there = await second.matches.load(id);
    expect(there.events, m.events);
    expect(there.state.currentInnings!.runs, 6);
    final list = await second.matches.watchAll().first;
    expect(list.single.summary, 'Lions 6/0 (0.2)');
  });

  test('a match scored on another phone is refreshed', () async {
    final first = device(deviceId: 'A');
    final (id, m) = await first.score(opening);
    await first.sync.pushPending();
    final second = device(deviceId: 'B');
    await second.sync.pull();

    await first.matches.append(id, m, m.apply(const Delivery.four()));
    await first.sync.pushPending();
    await second.sync.pull();
    expect((await second.matches.load(id)).state.currentInnings!.runs, 10);
  });

  test('changes not yet uploaded are never overwritten', () async {
    final first = device(deviceId: 'A');
    final (id, m) = await first.score(opening);
    await first.sync.pushPending();
    final second = device(deviceId: 'B');
    await second.sync.pull();

    // The second phone scores a ball offline.
    final there = await second.matches.load(id);
    await second.matches.append(id, there, there.apply(const Delivery.six()));
    // Meanwhile the first phone scores another.
    await first.matches.append(id, m, m.apply(const Delivery.dot()));
    await first.sync.pushPending();

    await second.sync.pull();
    expect((await second.matches.load(id)).state.currentInnings!.runs, 12);
  });

  test("other people's matches are not downloaded", () async {
    final mine = device(uid: 'u1');
    await mine.score(opening);
    await mine.sync.pushPending();
    final theirs = device(uid: 'u2');
    await theirs.sync.syncAll();
    expect(await theirs.matches.watchAll().first, isEmpty);
  });

  test('deleting a match removes it from the cloud too', () async {
    final phone = device();
    final (id, _) = await phone.score(opening);
    await phone.sync.pushPending();
    await phone.matches.delete(id);
    await phone.sync.syncAll();
    expect(await remoteMatch(id), isNull);
    expect(await remoteSeqs(id), isEmpty);
    expect(await phone.db.pendingDeletions(), isEmpty);

    // And it does not come back on another phone.
    final other = device();
    await other.sync.syncAll();
    expect(await other.matches.watchAll().first, isEmpty);
  });

  test('matches saved before signing in are claimed and uploaded', () async {
    final phone = device();
    final before = MatchRepository(phone.db);
    final id = await before.create(setup());
    await phone.sync.syncAll();
    final doc = (await remoteMatch(id))!;
    expect(doc['ownerUid'], 'u1');
  });

  test(
    'a long match uploads in several batches, each stating the owner',
    () async {
      final phone = device();
      final commits = <List<CloudWrite>>[];
      cloud.onCommit = commits.add;
      final events = <MatchEvent>[
        const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'),
        for (var over = 0; over < 50; over++) ...[
          BowlerSelected('B${11 - over % 5}'),
          for (var b = 0; b < 6; b++) const Delivery.runs(2),
        ],
        const OpenersSelected(strikerId: 'B1', nonStrikerId: 'B2'),
        for (var over = 0; over < 50; over++) ...[
          BowlerSelected('A${11 - over % 5}'),
          for (var b = 0; b < 6; b++) const Delivery.dot(),
        ],
      ];
      final (id, m) = await phone.score(events, rules: MatchRules.odi);
      expect(m.events.length, greaterThan(400));
      await phone.sync.pushPending();
      final matchCommits = commits.where((c) => c.length > 1).toList();
      expect(matchCommits.length, greaterThan(1));
      for (final c in matchCommits) {
        expect(
          c.whereType<CloudSet>().where(
            (w) => w.path == SyncService.matchPath(id),
          ),
          isNotEmpty,
        );
      }
      expect((await remoteSeqs(id)).length, m.events.length);
      expect((await remoteMatch(id))!['summary'], 'Lions won by 600 runs');
    },
  );

  test('a match still uploading is skipped by other phones', () async {
    await cloud.commit([
      const CloudSet('matches/half', {'ownerUid': 'u1'}, merge: true),
    ]);
    final phone = device();
    await phone.sync.pull();
    expect(await phone.matches.watchAll().first, isEmpty);
  });

  test('saved teams sync between phones', () async {
    final first = device();
    await first.teams.save(setup().teamA);
    await first.sync.syncAll();

    final second = device();
    await second.sync.syncAll();
    final teams = await second.teams.watchAll().first;
    expect(teams.single.name, 'Lions');
    expect(teams.single.players, hasLength(11));
    expect(teams.single.players.first.name, 'Lions 1');
  });
}
