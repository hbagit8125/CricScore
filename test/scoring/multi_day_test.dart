import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cric_score/app/router.dart';
import 'package:cric_score/data/providers.dart';
import 'package:cric_score/features/home/home_screen.dart';
import 'package:cric_score/features/scoring/scoring_logic.dart';
import 'package:cric_score/features/scoring/scoring_screen.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/app_harness.dart';
import 'scoring_flow_test.dart' show current, innings;

/// Records [events] as if scored, in one change, so the screen does not
/// ask questions part way through.
Future<void> record(AppHarness app, List<MatchEvent> events) async {
  final tester = app.tester;
  final screen = tester.widget<ScoringScreen>(find.byType(ScoringScreen));
  final controller = ProviderScope.containerOf(
    tester.element(find.byType(ScoringScreen)),
  ).read(matchControllerProvider(screen.matchId).notifier);
  await tester.runAsync(() => controller.replaceEvents(events));
  await app.settle();
}

/// Answers whatever the engine asks with its suggestion.
Match answer(Match m) {
  for (final q in m.state.pending) {
    m = switch (q) {
      ChooseBatter(:final suggested) => m.apply(BatterIn(suggested)),
      ChooseBowler(:final suggested?) => m.apply(BowlerSelected(suggested)),
      _ => m,
    };
  }
  return m;
}

/// [count] fours, with new bowlers as overs end.
Match fours(Match m, int count) {
  for (var i = 0; i < count; i++) {
    m = answer(m.apply(const Delivery.four()));
  }
  return m;
}

/// Bowls the batting side out, each striker bowled first ball.
Match allOut(Match m) {
  final number = m.state.currentInnings!.number;
  while (m.state.currentInnings!.number == number &&
      !m.state.currentInnings!.isClosed) {
    final striker = m.state.currentInnings!.strikerId!;
    m = answer(
      m.apply(
        Delivery.wicket(
          Dismissal(kind: DismissalKind.bowled, batterId: striker),
        ),
      ),
    );
  }
  return m;
}

Future<void> newMatch(AppHarness app, String format) async {
  await app.tap(find.text('New match'));
  await app.tap(find.text(format));
}

Future<void> startInnings(AppHarness app) async {
  await app.tapKey('startInnings');
  await app.tap(find.text('Suggested'));
}

Future<void> more(AppHarness app, String action, {String key = 'more'}) async {
  await app.tapKey(key);
  await app.tapInList('more-$action');
}

void main() {
  testWidgets('a two-day match: declare, follow-on, forfeit, innings win', (
    tester,
  ) async {
    final app = AppHarness(tester);
    await app.start();
    await newMatch(app, 'Custom');
    await app.tap(find.text('Two innings'));
    expect(find.textContaining('follow-on at 100'), findsOneWidget);
    await app.tapKey('startMatch');
    await startInnings(app);
    expect(find.text('Day 1 of 2'), findsOneWidget);

    await record(app, fours(current(tester), 26).events);
    expect(find.text('104/0'), findsOneWidget);
    await more(app, 'declare');
    await app.tapKey('confirm');
    expect(innings(tester).number, 2);

    // Team B start straight away and are bowled out for nothing.
    await startInnings(app);
    expect(find.textContaining('Trail by 104'), findsOneWidget);
    await record(app, allOut(current(tester)).events);
    expect(find.text('Follow-on'), findsOneWidget);
    await app.tap(find.text('Enforce'));
    final third = current(tester).state.currentInnings!;
    expect(third.number, 3);
    expect(current(tester).setup.team(third.battingTeamId).name, 'Team B');

    // They forfeit instead of batting again.
    await tester.tapAt(const Offset(10, 10));
    await app.settle();
    await more(app, 'forfeit', key: 'morePending');
    await app.tapKey('confirm');
    expect(
      tester.widget<Text>(find.byKey(const Key('result'))).data,
      'Team A won by an innings and 104 runs',
    );

    await app.tapKey('resultScorecard');
    expect(find.byKey(const Key('summaryTab')), findsOneWidget);
    expect(find.text('104/0d'), findsOneWidget);
    expect(find.text('forfeited'), findsOneWidget);
    await app.stop();
  });

  testWidgets('stumps ends the day and the next ball starts the next', (
    tester,
  ) async {
    final app = AppHarness(tester);
    await app.start();
    await newMatch(app, 'Test');
    expect(find.textContaining('5 days'), findsOneWidget);
    await app.tapKey('startMatch');
    await startInnings(app);
    expect(find.text('Day 1 of 5'), findsOneWidget);

    await app.tapKey('runs4');
    await more(app, 'stoppage');
    await app.tapKey('stop-stumps');
    expect(find.byKey(const Key('stopped')), findsOneWidget);
    expect(find.text('Stumps, day 1'), findsOneWidget);
    expect(find.text('Day 2 of 5'), findsOneWidget);

    await app.tapKey('runs1');
    expect(find.byKey(const Key('stopped')), findsNothing);
    expect(find.text('5/0'), findsOneWidget);

    await app.tapKey('scorecard');
    expect(find.text('CLOSE OF PLAY'), findsOneWidget);
    expect(find.text('Team A 4/0'), findsOneWidget);
    await app.stop();
  });

  testWidgets('stumps on the last day offers the draw', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await newMatch(app, 'Custom');
    await app.tap(find.text('Two innings'));
    await app.tap(
      find.descendant(
        of: find.byKey(const Key('customDays')),
        matching: find.byTooltip('Fewer'),
      ),
    );
    expect(find.textContaining('1 day'), findsOneWidget);
    await app.tapKey('startMatch');
    await startInnings(app);

    await more(app, 'stoppage');
    await app.tapKey('stop-stumps');
    expect(find.text('That was the last day'), findsOneWidget);
    await app.tapKey('confirm');
    expect(
      tester.widget<Text>(find.byKey(const Key('result'))).data,
      'Match drawn',
    );
    await app.stop();
  });

  testWidgets('a concussion replacement named on the day', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await newMatch(app, 'T20');
    await app.tapKey('startMatch');
    await startInnings(app);

    final setup = current(tester).setup;
    final fielding = setup.team(innings(tester).bowlingTeamId);
    final out = fielding.players.first.id;
    await more(app, 'substitute');
    await app.tapKey('sub-${fielding.id}');
    // The bowler cannot be replaced mid-over.
    expect(find.byKey(Key('subOut-${innings(tester).bowlerId}')), findsNothing);
    await app.tapInList('subOut-$out');
    await app.tapKey('subIn-new');
    await app.tapKey('subReason-concussion');
    await tester.enterText(find.byKey(const Key('textInput')), 'Sam Sub');
    await app.tapKey('saveText');

    final state = current(tester).state;
    final sub = state.substitutions.single;
    expect(sub.reason, SubstitutionReason.concussion);
    expect(sub.outPlayerId, out);
    expect(state.setup.team(fielding.id).substitutes.single.name, 'Sam Sub');
    expect(playingIds(state, fielding.id), contains(sub.inPlayerId));
    expect(playingIds(state, fielding.id), isNot(contains(out)));
    await app.stop();
  });

  testWidgets('a real Test with a follow-on replays through the app', (
    tester,
  ) async {
    // West Indies v India, 2016: India declared at 566/8, bowled West
    // Indies out for 243, enforced the follow-on and won by an innings.
    final json =
        jsonDecode(
              utf8.decode(
                gzip.decode(
                  File('test/fixtures/test_1022593.json.gz').readAsBytesSync(),
                ),
              ),
            )
            as Map<String, dynamic>;
    final setup = MatchJson.setupFromJson(
      json['setup'] as Map<String, Object?>,
    );
    final events = [
      for (final e in json['events'] as List)
        MatchJson.eventFromJson((e as Map).cast<String, Object?>()),
    ];
    final followOn = events.indexWhere((e) => e is FollowOn);
    expect(events[followOn], const FollowOn(enforce: true));

    final app = AppHarness(tester);
    await app.start();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    );
    final repo = container.read(matchRepositoryProvider);
    // Saved in two steps, letting the app see the new match in between.
    final id = (await tester.runAsync(() => repo.create(setup)))!;
    await app.settle();
    await tester.runAsync(
      () => repo.rewrite(id, Match.replay(setup, events.sublist(0, followOn))),
    );
    await app.settle();
    unawaited(
      GoRouter.of(
        tester.element(find.byType(HomeScreen)),
      ).push(Routes.match(id)),
    );
    await app.settle();

    // The scorer is asked about the follow-on, and enforces it.
    expect(
      find.text('India lead by 323. Make West Indies follow on?'),
      findsOneWidget,
    );
    await app.tap(find.text('Enforce'));
    expect(current(tester).events, events.sublist(0, followOn + 1));
    expect(
      find.textContaining('Follow-on · West Indies 243/10'),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10));
    await app.settle();

    // The rest of the match, as recorded at the ground.
    await record(app, events);
    final state = current(tester).state;
    expect(state.innings.map((i) => '${i.battingTeamId} ${inningsScore(i)}'), [
      'India 566/8d',
      'West Indies 243/10',
      'West Indies 231/10',
    ]);
    expect(
      tester.widget<Text>(find.byKey(const Key('result'))).data,
      'India won by an innings and 92 runs',
    );

    await app.tapKey('resultScorecard');
    expect(find.text('India 1st inns'), findsWidgets);
    expect(find.text('566/8d'), findsOneWidget);
    expect(find.text('West Indies 2nd inns'), findsWidgets);
    await app.stop();
  });
}
