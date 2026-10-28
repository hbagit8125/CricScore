import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';
import 'two_innings_test.dart' show batInnings, newTest, rules;

void main() {
  test('multi-day rules take the follow-on margin from the days', () {
    expect(MatchRules.test.days, 5);
    expect(MatchRules.firstClass.days, 4);
    final twoDay = MatchRules.multiDay(days: 2, playersPerSide: 9);
    expect(twoDay.isTwoInnings, isTrue);
    expect(twoDay.followOnMargin, 100);
    expect(twoDay.ballsPerInnings, isNull);
    expect(twoDay.validate(), isEmpty);
    expect(MatchRules.test.copyWith(days: 0).validate(), isNotEmpty);
  });

  test('stumps ends the day and records the close-of-play score', () {
    var m = newTest()
        .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
        .apply(const BowlerSelected('B3'))
        .bowl(2, const Delivery.four());
    expect(m.state.day, 1);
    m = m.apply(const Stoppage(StoppageKind.stumps));
    expect(m.state.day, 2);
    expect(m.state.stoppedFor, StoppageKind.stumps);
    final close = m.state.closeOfPlay.single;
    expect(close.day, 1);
    expect(close.runs, 8);
    expect(close.legalBalls, 2);
    expect(close.battingTeamId, 'LIO');
    expect(close.inningsClosed, isFalse);
    // The scorer state is otherwise unchanged: the over goes on.
    expect(m.inn.bowlerId, 'B3');
    expect(m.state.readyForDelivery, isTrue);
  });

  test('the next ball resumes play; lunch and tea do not change the day', () {
    var m = newTest()
        .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
        .apply(const BowlerSelected('B3'))
        .apply(const Stoppage(StoppageKind.lunch));
    expect(m.state.stoppedFor, StoppageKind.lunch);
    m = m.apply(const Delivery.dot());
    expect(m.state.stoppedFor, isNull);
    m = m
        .apply(const Stoppage(StoppageKind.tea))
        .apply(const Stoppage(StoppageKind.weather));
    expect(m.state.day, 1);
    expect(m.state.stoppedFor, StoppageKind.weather);
    expect(m.state.stoppages.map((s) => s.kind), [
      StoppageKind.lunch,
      StoppageKind.tea,
      StoppageKind.weather,
    ]);
  });

  test('a day lost to rain counts as a day', () {
    final m = newTest()
        .apply(const Stoppage(StoppageKind.stumps))
        .apply(const Stoppage(StoppageKind.stumps));
    expect(m.state.day, 3);
    expect(m.state.closeOfPlay.map((s) => s.runs), [0, 0]);
  });

  test('stumps at an innings break keeps the finished innings score', () {
    var m = batInnings(newTest(), 30);
    expect(m.inn.number, 2);
    m = m.apply(const Stoppage(StoppageKind.stumps));
    final close = m.state.closeOfPlay.single;
    expect(close.inningsNumber, 1);
    expect(close.runs, 30);
    expect(close.inningsClosed, isTrue);
  });

  test('play can stop while the follow-on is being decided', () {
    var m = batInnings(newTest(), 40);
    m = batInnings(m, 10);
    expect(m.state.pending.single, isA<ChooseFollowOn>());
    m = m.apply(const Stoppage(StoppageKind.stumps));
    expect(m.state.closeOfPlay.single.inningsNumber, 2);
    m = m.apply(const FollowOn(enforce: true));
    expect(m.inn.battingTeamId, 'TIG');
  });

  test('a draw at stumps on the last day', () {
    var m = batInnings(newTest(), 20);
    m = m.apply(const Stoppage(StoppageKind.stumps)).apply(const Drawn());
    expect(m.state.result, isA<Draw>());
    expect(m.state.stoppedFor, isNull);
    expect(
      () => m.apply(const Stoppage(StoppageKind.tea)),
      throwsIllegal(IllegalEventCode.matchOver),
    );
  });

  test('stoppages replay and undo like any other event', () {
    final m = newTest()
        .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
        .apply(const Stoppage(StoppageKind.stumps));
    expect(m.undo().state.day, 1);
    expect(Match.replay(m.setup, m.events).state.day, 2);
    expect(rules.isTwoInnings, isTrue);
  });
}
