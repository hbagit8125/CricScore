import 'package:flutter_test/flutter_test.dart';
import 'package:cric_score/models/ball_event.dart';
import 'package:cric_score/models/player.dart';
import 'package:cric_score/providers/match_provider.dart';

BallEvent runs(int r) {
  const types = {0: BallType.dot, 1: BallType.one, 2: BallType.two, 3: BallType.three, 4: BallType.four, 6: BallType.six};
  return BallEvent(type: types[r]!, runs: r, extras: 0, isWicket: false, isLegalBall: true);
}

BallEvent wide() => BallEvent(type: BallType.wide, runs: 0, extras: 1, isWicket: false, isLegalBall: false);
BallEvent wide4() => BallEvent(type: BallType.wide4, runs: 0, extras: 5, isWicket: false, isLegalBall: false);
BallEvent noBall() => BallEvent(type: BallType.noBall, runs: 0, extras: 1, isWicket: false, isLegalBall: false);
BallEvent wicket() => BallEvent(type: BallType.wicket, runs: 0, extras: 0, isWicket: true, isLegalBall: true, wicketType: "Bowled");

MatchProvider startMatch({int players = 3}) {
  final a = List.generate(players, (i) => Player(id: "A$i", name: "A${i + 1}"));
  final b = List.generate(players, (i) => Player(id: "B$i", name: "B${i + 1}"));
  final match = MatchProvider()..initMatch("Test", players, "Lions", "Tigers", a, b);
  match.startMatch(match.teamA!, match.teamB!, a[0], a[1], b[0]);
  return match;
}

void main() {
  group('scoring', () {
    test('runs off the bat go to team, batter and bowler', () {
      final match = startMatch();
      final striker = match.currentStriker!;
      match.processBall(runs(4));
      match.processBall(runs(6));

      expect(match.battingTeam!.totalRuns, 10);
      expect(match.battingTeam!.ballsFaced, 2);
      expect(striker.runsScored, 10);
      expect(striker.ballsFaced, 2);
      expect(striker.fours, 1);
      expect(striker.sixes, 1);
      expect(match.currentBowler!.runsConceded, 10);
      expect(match.currentBowler!.ballsBowled, 2);
    });

    test('wides are extras and not balls faced', () {
      final match = startMatch();
      final striker = match.currentStriker!;
      match.processBall(wide());
      match.processBall(wide4());

      expect(match.battingTeam!.totalRuns, 6);
      expect(match.battingTeam!.extras, 6);
      expect(match.battingTeam!.ballsFaced, 0);
      expect(striker.ballsFaced, 0);
      expect(striker.runsScored, 0);
    });

    test('no-ball is an extra but is faced by the batter', () {
      final match = startMatch();
      final striker = match.currentStriker!;
      match.processBall(noBall());

      expect(match.battingTeam!.totalRuns, 1);
      expect(match.battingTeam!.ballsFaced, 0);
      expect(striker.ballsFaced, 1);
    });
  });

  group('strike rotation', () {
    test('odd runs swap ends, even runs do not', () {
      final match = startMatch();
      final a1 = match.currentStriker!;
      final a2 = match.currentNonStriker!;

      match.processBall(runs(2));
      expect(match.currentStriker, a1);
      match.processBall(runs(1));
      expect(match.currentStriker, a2);
    });

    test('end of over swaps ends', () {
      final match = startMatch();
      final a1 = match.currentStriker!;
      for (var i = 0; i < 6; i++) {
        match.processBall(runs(0));
      }
      expect(match.isOverComplete, isTrue);
      expect(match.currentStriker, isNot(a1));
    });

    test('single off the last ball keeps the striker on strike', () {
      final match = startMatch();
      final a1 = match.currentStriker!;
      for (var i = 0; i < 5; i++) {
        match.processBall(runs(0));
      }
      match.processBall(runs(1));
      expect(match.currentStriker, a1);
    });
  });

  group('new batter', () {
    test('available batters exclude both players at the crease', () {
      final match = startMatch(players: 5);
      match.processBall(wicket());

      final names = match.availableBatsmen.map((p) => p.name).toList();
      expect(names, ['A3', 'A4', 'A5']);
    });

    test('wicket on the last ball of the over does not offer the surviving batter', () {
      final match = startMatch();
      final a1 = match.currentStriker!;
      final a2 = match.currentNonStriker!;
      for (var i = 0; i < 5; i++) {
        match.processBall(runs(0));
      }
      match.processBall(wicket());

      expect(a1.isOut, isTrue);
      expect(match.availableBatsmen, isNot(contains(a2)));
      expect(match.availableBatsmen.map((p) => p.name), ['A3']);
    });

    test('new batter replaces the dismissed player in whichever slot they are in', () {
      final match = startMatch();
      final a2 = match.currentNonStriker!;
      for (var i = 0; i < 5; i++) {
        match.processBall(runs(0));
      }
      match.processBall(wicket());
      final a3 = match.availableBatsmen.single;
      match.setNewBatsman(a3);

      expect({match.currentStriker, match.currentNonStriker}, {a2, a3});
    });
  });

  group('all out', () {
    test('team is all out when one batter is left', () {
      final match = startMatch();
      match.processBall(wicket());
      expect(match.isAllOut, isFalse);
      match.setNewBatsman(match.availableBatsmen.single);
      match.processBall(wicket());

      expect(match.isAllOut, isTrue);
      expect(match.availableBatsmen, isEmpty);
    });

    test('balls after all out are ignored', () {
      final match = startMatch();
      match.processBall(runs(4));
      match.processBall(wicket());
      match.setNewBatsman(match.availableBatsmen.single);
      match.processBall(wicket());
      match.processBall(runs(6));

      expect(match.battingTeam!.totalRuns, 4);
      expect(match.battingTeam!.ballsFaced, 3);
    });
  });

  group('run rate', () {
    test('is zero before any legal ball', () {
      final match = startMatch();
      expect(match.currentRunRate, 0.0);
      match.processBall(wide());
      expect(match.currentRunRate, 0.0);
    });

    test('is runs per six legal balls', () {
      final match = startMatch();
      match.processBall(runs(4));
      expect(match.currentRunRate, 24.0);

      for (final r in [1, 2, 1, 1]) {
        match.processBall(runs(r));
      }
      match.processBall(wide());
      match.processBall(runs(0));
      // 10 runs off 6 legal balls
      expect(match.currentRunRate, 10.0);
    });
  });

  test('starting a new match clears the previous over history', () {
    final match = startMatch();
    match.processBall(runs(1));
    match.startNewOver(match.teamB!.players[1]);
    expect(match.inningsHistory, hasLength(1));

    final a = [Player(id: "A0", name: "X"), Player(id: "A1", name: "Y")];
    final b = [Player(id: "B0", name: "Z"), Player(id: "B1", name: "W")];
    match.initMatch("Second", 2, "One", "Two", a, b);
    expect(match.inningsHistory, isEmpty);
    expect(match.currentOver, isEmpty);
  });
}
