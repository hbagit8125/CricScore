import 'package:cric_score/auth/auth_providers.dart';
import 'package:cric_score/data/local/app_database.dart';
import 'package:cric_score/data/match_repository.dart';
import 'package:cric_score/data/providers.dart';
import 'package:cric_score/data/team_repository.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_auth.dart';

MatchSetup setup({MatchRules rules = MatchRules.t20}) {
  TeamSheet team(String id, String name, String prefix) => TeamSheet(
    id: id,
    name: name,
    players: [
      for (var i = 1; i <= rules.playersPerSide; i++)
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

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ProviderContainer container;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authServiceProvider.overrideWithValue(
          FakeAuthService(signedIn: FakeAuthService.testUser),
        ),
      ],
    );
    // Sign-in state arrives asynchronously, as in the app.
    container.listen(currentUidProvider, (_, _) {});
    await container.read(authStateProvider.future);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  MatchRepository repo() => container.read(matchRepositoryProvider);

  Future<MatchController> controllerFor(String id) async {
    await container.read(matchControllerProvider(id).future);
    return container.read(matchControllerProvider(id).notifier);
  }

  test('a new match is listed as not started', () async {
    await repo().create(setup());
    final list = await repo().watchAll().first;
    expect(list.single.title, 'Lions v Tigers');
    expect(list.single.format, 'T20');
    expect(list.single.status, MatchStatus.inProgress);
    expect(list.single.summary, 'Not started');
  });

  test('every event is saved and the match reloads exactly', () async {
    final id = await repo().create(setup());
    final c = await controllerFor(id);
    await c.apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'));
    await c.apply(const BowlerSelected('B11'));
    await c.apply(const Delivery.four());
    await c.apply(const Delivery.noBall(runs: 1));

    // A fresh repository on the same database: as after an app restart.
    final reloaded = await MatchRepository(db).load(id);
    expect(
      reloaded.events,
      container.read(matchControllerProvider(id)).value!.events,
    );
    expect(reloaded.state.currentInnings!.runs, 6);
    expect(reloaded.state.currentInnings!.freeHitNext, isTrue);
    expect((await repo().watchAll().first).single.summary, 'Lions 6/0 (0.1)');
  });

  test('a refused event is not saved and the match is unchanged', () async {
    final id = await repo().create(setup());
    final c = await controllerFor(id);
    await expectLater(
      c.apply(const Delivery.dot()),
      throwsA(isA<IllegalEventException>()),
    );
    expect((await MatchRepository(db).load(id)).events, isEmpty);
    // The controller keeps working after a refusal.
    await c.apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'));
    expect((await MatchRepository(db).load(id)).events, hasLength(1));
  });

  test('undo and edits rewrite the stored log', () async {
    final id = await repo().create(setup());
    final c = await controllerFor(id);
    for (final e in const [
      OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'),
      BowlerSelected('B11'),
      Delivery.runs(1),
      Delivery.six(),
    ]) {
      await c.apply(e);
    }
    await c.undo();
    expect((await MatchRepository(db).load(id)).events, hasLength(3));
    await c.replaceAt(2, const Delivery.runs(3));
    final m = await MatchRepository(db).load(id);
    expect(m.state.currentInnings!.runs, 3);
    expect(m.state.currentInnings!.strikerId, 'A2');
  });

  test('taps in quick succession are stored in order', () async {
    final id = await repo().create(setup());
    final c = await controllerFor(id);
    await c.apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'));
    await c.apply(const BowlerSelected('B11'));
    await Future.wait([
      for (var i = 0; i < 6; i++) c.apply(Delivery.runs(i.isEven ? 1 : 2)),
    ]);
    final m = await MatchRepository(db).load(id);
    expect(m.state.currentInnings!.runs, 9);
    expect(m.state.currentInnings!.oversText, '1.0');
  });

  test('a finished match is marked complete with its result', () async {
    final id = await repo().create(
      setup(rules: MatchRules.custom(overs: 1, playersPerSide: 3)),
    );
    final c = await controllerFor(id);
    final events = <MatchEvent>[
      const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'),
      const BowlerSelected('B3'),
      ...List.filled(6, const Delivery.runs(2)),
      const OpenersSelected(strikerId: 'B1', nonStrikerId: 'B2'),
      const BowlerSelected('A3'),
      ...List.filled(6, const Delivery.dot()),
    ];
    for (final e in events) {
      await c.apply(e);
    }
    final list = await repo().watchAll().first;
    expect(list.single.status, MatchStatus.complete);
    expect(list.single.summary, 'Lions won by 12 runs');
  });

  test('deleting a match removes its events', () async {
    final id = await repo().create(setup());
    final c = await controllerFor(id);
    await c.apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'));
    await repo().delete(id);
    expect(await repo().watchAll().first, isEmpty);
    expect(await db.select(db.matchEvents).get(), isEmpty);
  });

  test('a whole Test match is stored and reloads identically', () async {
    final s = setup(rules: MatchRules.test.copyWith(playersPerSide: 3));
    final id = await repo().create(s);
    var m = Match.start(s);
    // Each side scores 10 then loses both wickets, four times over.
    for (var inn = 0; inn < 4 && !m.state.isComplete; inn++) {
      final batting = m.state.currentInnings!.battingTeamId == 'LIO'
          ? 'A'
          : 'B';
      final bowling = batting == 'A' ? 'B' : 'A';
      final before = m;
      m = m
          .apply(
            OpenersSelected(
              strikerId: '${batting}1',
              nonStrikerId: '${batting}2',
            ),
          )
          .apply(BowlerSelected('${bowling}3'))
          .apply(const Delivery.four())
          .apply(const Delivery.six())
          .apply(
            Delivery.wicket(
              Dismissal(kind: DismissalKind.bowled, batterId: '${batting}1'),
            ),
          )
          .apply(BatterIn('${batting}3'))
          .apply(
            Delivery.wicket(
              Dismissal(kind: DismissalKind.bowled, batterId: '${batting}3'),
            ),
          );
      await repo().append(id, before, m);
    }
    final reloaded = await MatchRepository(db).load(id);
    expect(reloaded.events, m.events);
    expect(reloaded.state.result, isA<Tie>());
  });

  test('teams are saved with players in batting order', () async {
    final teams = TeamRepository(db);
    final lions = setup().teamA;
    await teams.save(lions);
    var saved = await teams.watchAll().first;
    expect(saved.single.name, 'Lions');
    expect(saved.single.players.map((p) => p.name).take(2), [
      'Lions 1',
      'Lions 2',
    ]);

    // Saving again replaces the line-up.
    await teams.save(
      TeamSheet(
        id: 'LIO',
        name: 'Lions',
        players: lions.players.reversed.toList(),
      ),
    );
    saved = await teams.watchAll().first;
    expect(saved.single.players.first.name, 'Lions 11');
    expect(saved.single.players, hasLength(11));
  });
}
