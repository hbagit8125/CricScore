import 'package:cric_score/data/providers.dart';
import 'package:cric_score/features/scoring/scoring_screen.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/app_harness.dart';

/// The match on screen, as the engine sees it.
Match current(WidgetTester tester) {
  final screen = tester.widget<ScoringScreen>(find.byType(ScoringScreen));
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ScoringScreen)),
  );
  return container.read(matchControllerProvider(screen.matchId)).value!;
}

InningsState innings(WidgetTester tester) =>
    current(tester).state.currentInnings!;

/// From home to the first ball: New match, Start match, Start innings,
/// suggested bowler.
Future<void> startMatch(AppHarness app, {String? format}) async {
  await app.tap(find.text('New match'));
  if (format != null) await app.tap(find.text(format));
  await app.tapKey('startMatch');
  await app.tapKey('startInnings');
  await app.tap(find.text('Suggested'));
}

void main() {
  p3b();

  testWidgets('a new match starts in four taps from home', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    expect(app.taps, 4);
    expect(find.byKey(const Key('runs1')), findsOneWidget);
    expect(find.text('0/0'), findsOneWidget);
    expect(find.text('0.0 ov'), findsOneWidget);
    await app.stop();
  });

  testWidgets('runs and extras', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);

    await app.tapKey('runs1');
    expect(find.text('1/0'), findsOneWidget);
    expect(find.text('0.1 ov'), findsOneWidget);

    // A wide with one run taken: two taps, two wides, not a ball.
    await app.tapKey('extra-wide');
    expect(find.byKey(const Key('armedHint')), findsOneWidget);
    await app.tapKey('runs1');
    expect(find.text('3/0'), findsOneWidget);
    expect(find.text('0.1 ov'), findsOneWidget);
    expect(find.text('2wd'), findsOneWidget);

    // A no-ball hit for four, then the free hit is shown.
    await app.tapKey('extra-noBall');
    await app.tapKey('runs4');
    expect(find.text('8/0'), findsOneWidget);
    expect(find.text('nb4'), findsOneWidget);
    expect(find.text('Free hit'), findsOneWidget);

    // Byes cannot be six.
    await app.tapKey('extra-byes');
    final six = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('runs6')),
        matching: find.byType(InkWell),
      ),
    );
    expect(six.onTap, isNull);
    await app.tapKey('runs2');
    expect(find.text('10/0'), findsOneWidget);
    expect(innings(tester).extras.byes, 2);
    await app.stop();
  });

  testWidgets('bowled: two taps, the next batter comes in, undo restores', (
    tester,
  ) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    final opener = innings(tester).strikerId;

    app.taps = 0;
    await app.tapKey('wicket');
    await app.tapKey('out-bowled');
    expect(app.taps, 2);
    expect(find.text('0/1'), findsOneWidget);
    expect(find.textContaining('comes in'), findsOneWidget);
    final inn = innings(tester);
    expect(inn.strikerId, isNot(opener));
    expect(inn.strikerId, isNotNull);

    await app.tapKey('undo');
    expect(find.text('0/0'), findsOneWidget);
    expect(innings(tester).strikerId, opener);
    await app.stop();
  });

  testWidgets('caught with the fielder, and changing who came in', (
    tester,
  ) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);

    await app.tapKey('wicket');
    await app.tapKey('out-caught');
    final fielder = current(
      tester,
    ).setup.team(innings(tester).bowlingTeamId).players[3];
    await app.tapKey('fielder-${fielder.id}');
    final out = innings(tester).batters.first;
    expect(out.dismissal!.kind, DismissalKind.caught);
    expect(out.dismissal!.fielderId, fielder.id);

    final suggested = innings(tester).strikerId!;
    await app.tap(find.text('Change'));
    final batting = current(
      tester,
    ).setup.team(innings(tester).battingTeamId).players;
    final other = batting.lastWhere((p) => p.id != suggested);
    await app.tapKey('batter-${other.id}');
    expect(innings(tester).strikerId, other.id);
    expect(innings(tester).batter(suggested), isNull);
    await app.stop();
  });

  testWidgets('run out of the non-striker after a completed run', (
    tester,
  ) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    final nonStriker = innings(tester).nonStrikerId!;

    await app.tapKey('wicket');
    await app.tapKey('out-runOut');
    await app.tapKey('outBatter-$nonStriker');
    await app.tapKey('completed-1');
    expect(find.text('1/1'), findsOneWidget);
    expect(innings(tester).batter(nonStriker)!.status, BatterStatus.out);
    await app.stop();
  });

  testWidgets('a refused action is explained and nothing changes', (
    tester,
  ) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    await app.tapKey('runs1');
    // Caught off a no-ball is not possible; it is not even offered.
    await app.tapKey('extra-noBall');
    await app.tapKey('wicket');
    final caught = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const Key('out-caught')),
        matching: find.byType(InkWell),
      ),
    );
    expect(caught.onTap, isNull);
    await app.stop();
  });

  testWidgets('a full T20 within the tap budget', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    expect(app.taps, 4, reason: 'New match, Start match, openers, bowler');

    final budget = <String, int>{};
    Future<void> spend(String action, Future<void> Function() act) async {
      final before = app.taps;
      await act();
      budget[action] = (budget[action] ?? 0) + app.taps - before;
    }

    var balls = 0;
    var wickets = 0;
    var extras = 0;
    var overChanges = 0;

    Future<void> playInnings({required bool attack}) async {
      for (var over = 0; over < 20; over++) {
        for (var ball = 0; ball < 6; ball++) {
          if (attack && ball == 2 && over.isOdd) {
            await spend('wide', () async {
              await app.tapKey('extra-wide');
              await app.tapKey('runs0');
            });
            extras++;
          }
          if (attack && ball == 5 && over % 7 == 6) {
            await spend('bowled', () async {
              await app.tapKey('wicket');
              await app.tapKey('out-bowled');
            });
            wickets++;
          } else {
            await spend('ball', () => app.tapKey(attack ? 'runs1' : 'runs0'));
          }
          balls++;
        }
        if (find.text('Suggested').evaluate().isNotEmpty) {
          await spend('over', () => app.tap(find.text('Suggested')));
          overChanges++;
        }
      }
    }

    await playInnings(attack: true);
    // Innings break: the openers sheet opens by itself with the summary;
    // one tap to start, one for the bowler.
    expect(find.byKey(const Key('inningsBreak')), findsOneWidget);
    final note = tester.widget<Text>(find.byKey(const Key('inningsBreak')));
    expect(note.data, contains('need'));
    await spend('innings break', () async {
      await app.tapKey('startInnings');
      await app.tap(find.text('Suggested'));
    });
    await playInnings(attack: false);

    expect(find.byKey(const Key('result')), findsOneWidget);
    expect(find.textContaining('won by'), findsOneWidget);

    // One tap per ordinary ball, two per wide and per bowled wicket, one per
    // over change, two at the innings break.
    expect(budget['ball'], balls - wickets);
    expect(budget['wide'], 2 * extras);
    expect(budget['bowled'], 2 * wickets);
    expect(budget['over'], overChanges);
    expect(budget['innings break'], 2);
    expect(balls, 240);
    expect(overChanges, 38, reason: '19 changes in each innings');
    await app.stop();
  }, timeout: const Timeout(Duration(minutes: 10)));
}

void p3b() {
  testWidgets('tapping a recorded ball corrects it', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    await app.tapKey('runs1');
    final ball = innings(tester).overs.last.deliveries.single;
    await app.tapKey('ball-${ball.eventIndex}');
    await app.tapKey('edit-runs4');
    expect(find.text('4/0'), findsOneWidget);
    expect(innings(tester).batters.first.fours, 1);
    await app.stop();
  });

  testWidgets('More: retire hurt, then penalty runs', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    final striker = innings(tester).strikerId!;

    await app.tapKey('more');
    await app.tapKey('more-retire');
    await app.tapKey('retire-$striker-hurt');
    expect(innings(tester).batter(striker)!.status, BatterStatus.retiredNotOut);
    expect(innings(tester).strikerId, isNot(striker));
    expect(innings(tester).wickets, 0);

    await app.tapKey('more');
    await app.tapInList('more-penalty');
    await app.tapKey('penalty-${innings(tester).battingTeamId}');
    expect(find.text('5/0'), findsOneWidget);
    await app.stop();
  });

  testWidgets('the umpire lets a bowler bowl a second over in a row', (
    tester,
  ) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    final bowler = innings(tester).bowlerId!;
    for (var i = 0; i < 6; i++) {
      await app.tapKey('runs0');
    }
    await app.tapInList('bowler-$bowler');
    await app.tapKey('umpireAllowed');
    expect(innings(tester).bowlerId, bowler);
    final last = current(tester).events.last as BowlerSelected;
    expect(last.umpireAllowed, isTrue);
    await app.stop();
  });

  testWidgets('rename a player mid-match', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    final striker = innings(tester).strikerId!;
    await app.tapKey('more');
    await app.tapInList('more-renamePlayer');
    await app.tapInList('rename-$striker');
    await tester.enterText(find.byKey(const Key('newName')), 'Babar Azam');
    await app.tapKey('saveName');
    expect(find.text('Babar Azam'), findsOneWidget);
    await app.stop();
  });

  testWidgets('abandon gives no result, and undo takes it back', (
    tester,
  ) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    await app.tapKey('more');
    await app.tapInList('more-abandon');
    await app.tapKey('confirm');
    expect(find.byKey(const Key('result')), findsOneWidget);
    expect(current(tester).state.result, isA<NoResult>());
    await app.tap(find.text('Undo last ball'));
    expect(current(tester).state.result, isNull);
    await app.stop();
  });

  testWidgets('scorecard and charts', (tester) async {
    final app = AppHarness(tester);
    await app.start();
    await startMatch(app);
    final striker = innings(tester).strikerId!;
    for (final k in ['runs4', 'runs1', 'runs6', 'runs0', 'runs2', 'runs1']) {
      await app.tapKey(k);
    }
    await app.tap(find.text('Suggested'));
    await app.tapKey('runs1');

    await app.tapKey('scorecard');
    expect(find.byKey(Key('bat-$striker')), findsOneWidget);
    expect(find.text('Fall of wickets'.toUpperCase()), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Over 1'),
      200,
      scrollable: find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first,
    );
    expect(find.text('Over 1'), findsOneWidget);

    await app.tapKey('chartsTab');
    expect(find.byKey(const Key('worm')), findsOneWidget);
    expect(find.byKey(const Key('manhattan')), findsOneWidget);
    await app.tap(find.byKey(const Key('manhattan')));
    expect(find.byKey(const Key('chartReadout')), findsOneWidget);
    await app.stop();
  });
}
