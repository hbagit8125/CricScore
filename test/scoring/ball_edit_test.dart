import 'package:cric_score/features/scoring/ball_edit.dart';
import 'package:cric_score/features/scoring/scoring_logic.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter_test/flutter_test.dart';

TeamSheet _team(String id) => TeamSheet(
  id: id,
  name: id,
  players: [
    for (var i = 1; i <= 11; i++) PlayerRef(id: '$id$i', name: '$id $i'),
  ],
);

/// Two overs bowled: B11 then B10, then one ball of the third by B11.
Match _twoOvers({Delivery third = const Delivery.dot()}) {
  var m = Match.start(
    MatchSetup(
      rules: MatchRules.t20,
      teamA: _team('A'),
      teamB: _team('B'),
      toss: const Toss(wonByTeamId: 'A', decision: TossDecision.bat),
    ),
  );
  m = m
      .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
      .apply(const BowlerSelected('B11'));
  for (var i = 0; i < 6; i++) {
    m = m.apply(i == 2 ? third : const Delivery.dot());
    if (i == 2 && third.dismissal != null) m = m.apply(const BatterIn('A3'));
  }
  m = m.apply(const BowlerSelected('B10'));
  for (var i = 0; i < 6; i++) {
    m = m.apply(const Delivery.runs(1));
  }
  return m.apply(const BowlerSelected('B11')).apply(const Delivery.dot());
}

DeliveryRecord _ball(Match m, int over, int index) =>
    m.state.currentInnings!.overs[over].deliveries[index];

Match _replay(Match m, List<MatchEvent> events) =>
    Match.replay(m.setup, events);

void main() {
  test('changing runs keeps the overs as they were', () {
    final m = _twoOvers();
    final fixed = correctedLog(
      m,
      _ball(m, 0, 2),
      const BallEdit.change(Delivery.four()),
    );
    expect(fixed.note, isNull);
    final after = _replay(m, fixed.events);
    expect(after.state.currentInnings!.runs, 10);
    expect(after.state.currentInnings!.legalBalls, 13);
  });

  test('a ball that was really a wide: the over stands as called', () {
    final m = _twoOvers();
    final fixed = correctedLog(
      m,
      _ball(m, 0, 2),
      const BallEdit.change(Delivery.wide()),
    );
    expect(fixed.note, contains('Over 1 now has 5 balls'));
    final inn = _replay(m, fixed.events).state.currentInnings!;
    expect(inn.overs[0].bowlerIds, ['B11']);
    expect(inn.overs[1].bowlerIds, ['B10']);
    expect(inn.bowler('B10')!.legalBalls, 6);
    expect(inn.legalBalls, 12);
  });

  test('removing a ball keeps later overs with their bowlers', () {
    final m = _twoOvers();
    final fixed = correctedLog(m, _ball(m, 1, 0), const BallEdit.remove());
    final inn = _replay(m, fixed.events).state.currentInnings!;
    expect(inn.bowler('B10')!.legalBalls, 5);
    expect(inn.bowler('B11')!.legalBalls, 7);
    expect(inn.overs[2].bowlerIds, ['B11']);
  });

  test('a missed ball added to a finished over: the umpire allowed seven', () {
    final m = _twoOvers();
    final fixed = correctedLog(
      m,
      _ball(m, 1, 3),
      const BallEdit.insertBefore(Delivery.four()),
    );
    expect(fixed.note, contains('Over 2 now has 7 balls'));
    final inn = _replay(m, fixed.events).state.currentInnings!;
    expect(inn.bowler('B10')!.legalBalls, 7);
    expect(inn.overs[2].bowlerIds, ['B11']);
    expect(inn.runs, 10);
  });

  test('a ball added to the over in progress just joins it', () {
    final m = _twoOvers();
    final fixed = correctedLog(
      m,
      _ball(m, 2, 0),
      const BallEdit.insertBefore(Delivery.runs(2)),
    );
    expect(fixed.note, isNull);
    final inn = _replay(m, fixed.events).state.currentInnings!;
    expect(inn.overs[2].deliveries, hasLength(2));
  });

  test('removing a wicket brings the batter back', () {
    final m = _twoOvers(
      third: const Delivery.wicket(
        Dismissal(kind: DismissalKind.bowled, batterId: 'A1'),
      ),
    );
    // The wicket made A3 come in; the log has BatterIn('A3') after it.
    expect(m.events, contains(const BatterIn('A3')));
    final fixed = correctedLog(
      m,
      _ball(m, 0, 2),
      const BallEdit.change(Delivery.dot()),
    );
    expect(fixed.events, isNot(contains(const BatterIn('A3'))));
    final inn = _replay(m, fixed.events).state.currentInnings!;
    expect(inn.wickets, 0);
    expect(inn.batter('A3'), isNull);
  });

  group('overs typed by the scorer', () {
    test('parse', () {
      expect(parseOvers('20', 6), 120);
      expect(parseOvers(' 7.3 ', 6), 45);
      expect(parseOvers('7.6', 6), isNull);
      expect(parseOvers('0', 6), isNull);
      expect(parseOvers('abc', 6), isNull);
    });

    test('format', () {
      expect(oversText(120, 6), '20');
      expect(oversText(45, 6), '7.3');
    });
  });
}
