import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late Match m;
  setUp(() => m = started(MatchRules.t20));

  test('no bowler bowls two overs in a row (Law 17.6)', () {
    m = m.bowl(6);
    final q = m.state.pending.single as ChooseBowler;
    expect(q.ineligible['B11'], BowlerIneligibility.bowledPreviousOver);
    expect(q.eligible, isNot(contains('B11')));
    expect(
      () => m.over('B11'),
      throwsIllegal(IllegalEventCode.bowlerIneligible),
    );
    m = m.over('B10').bowl(6).over('B11');
    expect(m.inn.bowlerId, 'B11');
  });

  test('only fielding players can bowl', () {
    expect(
      () => m.bowl(6).over('A5'),
      throwsIllegal(IllegalEventCode.notInBowlingTeam),
    );
  });

  test('bowlers stop at their quota', () {
    m = started(MatchRules.t10);
    m = m.bowl(6).over('B10').bowl(6).over('B11').bowl(6).over('B10').bowl(6);
    final q = m.state.pending.single as ChooseBowler;
    expect(q.ineligible['B11'], BowlerIneligibility.quotaReached);
    expect(m.inn.bowlerMaxBalls, 12);
  });

  test('the quota follows a reduced innings', () {
    m = m.apply(const RevisedTarget(ballsPerInnings: 42));
    expect(m.inn.bowlerMaxBalls, 12);
  });

  test('the suggested bowler alternates ends', () {
    m = m.bowl(6).over('B10').bowl(6);
    expect((m.state.pending.single as ChooseBowler).suggested, 'B11');
  });

  test('before the first over the suggestion comes from the tail', () {
    final fresh = Match.start(
      setupFor(MatchRules.t20),
    ).apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'));
    expect((fresh.state.pending.single as ChooseBowler).suggested, 'B11');
  });

  test('the bowler can be changed before the over starts', () {
    m = m.over('B9');
    expect(m.inn.bowlerId, 'B9');
    expect(m.inn.currentOver!.bowlerIds, ['B9']);
  });

  group('bowler unable to finish the over (Law 17.8)', () {
    test('another bowler completes it; the over is no one\'s maiden', () {
      m = m.bowl(6).over('B10').bowl(2);
      final options = m.bowlerOptions(midOver: true);
      expect(options.ineligible['B11'], BowlerIneligibility.bowledPreviousOver);
      expect(options.ineligible['B10'], BowlerIneligibility.currentBowler);
      m = m.over('B9').bowl(4);
      expect(m.inn.bowler('B10')!.legalBalls, 2);
      expect(m.inn.bowler('B9')!.legalBalls, 4);
      expect(m.inn.overs[1].bowlerIds, ['B10', 'B9']);
      expect(m.inn.bowler('B9')!.maidens, 0);
      expect(m.inn.bowler('B10')!.maidens, 0);
    });

    test('neither of them may bowl the next over', () {
      m = m.bowl(2).over('B9').bowl(4);
      final q = m.state.pending.single as ChooseBowler;
      expect(q.ineligible.keys, containsAll(['B11', 'B9']));
    });
  });

  test('The Hundred allows ten balls in a row but not fifteen', () {
    m = started(MatchRules.hundred).bowl(5).over('B11').bowl(5);
    final q = m.state.pending.single as ChooseBowler;
    expect(q.ineligible['B11'], BowlerIneligibility.bowledPreviousOver);
  });
}
