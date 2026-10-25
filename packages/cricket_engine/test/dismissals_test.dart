import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

Delivery out(
  DismissalKind kind,
  String batter, {
  String? fielder,
  int runs = 0,
}) => Delivery.wicket(
  Dismissal(kind: kind, batterId: batter, fielderId: fielder),
  runs: runs,
);

void main() {
  late Match m;
  setUp(() => m = started(MatchRules.t20));

  group('credit', () {
    for (final kind in [
      DismissalKind.bowled,
      DismissalKind.caught,
      DismissalKind.lbw,
      DismissalKind.stumped,
      DismissalKind.hitWicket,
    ]) {
      test('${kind.name} is credited to the bowler', () {
        m = m.apply(out(kind, 'A1'));
        expect(m.inn.wickets, 1);
        expect(m.inn.bowler('B11')!.wickets, 1);
        expect(m.inn.batter('A1')!.dismissal!.bowlerId, 'B11');
      });
    }

    for (final kind in [
      DismissalKind.runOut,
      DismissalKind.obstructingTheField,
      DismissalKind.hitTheBallTwice,
    ]) {
      test('${kind.name} is not credited to the bowler', () {
        m = m.apply(out(kind, 'A1'));
        expect(m.inn.wickets, 1);
        expect(m.inn.bowler('B11')!.wickets, 0);
        expect(m.inn.batter('A1')!.dismissal!.bowlerId, isNull);
      });
    }
  });

  group('next batter', () {
    test('a wicket asks for the next batter in order', () {
      m = m.apply(out(DismissalKind.bowled, 'A1'));
      final q = m.state.pending.single as ChooseBatter;
      expect(q.suggested, 'A3');
      expect(q.candidates.first, 'A3');
      expect(q.candidates, isNot(contains('A2')));
      expect(q.atStrikersEnd, isTrue);
      expect(
        () => m.apply(const Delivery.dot()),
        throwsIllegal(IllegalEventCode.batterNeeded),
      );
      m = m.apply(const BatterIn('A3'));
      expect(m.inn.strikerId, 'A3');
      expect(m.inn.nonStrikerId, 'A2');
    });

    test('the batter at the other end cannot come in again', () {
      m = m.apply(out(DismissalKind.bowled, 'A1'));
      expect(
        () => m.apply(const BatterIn('A2')),
        throwsIllegal(IllegalEventCode.batterUnavailable),
      );
      expect(
        () => m.apply(const BatterIn('A1')),
        throwsIllegal(IllegalEventCode.batterUnavailable),
      );
    });

    test('caught off the last ball: new batter at the striker\'s end, '
        'the other batter faces the next over', () {
      m = m.bowl(5).apply(out(DismissalKind.caught, 'A1', fielder: 'B3'));
      expect(m.inn.batter('A1')!.dismissal!.fielderId, 'B3');
      final q = m.state.pending.whereType<ChooseBatter>().single;
      expect(q.atStrikersEnd, isFalse);
      m = m.apply(const BatterIn('A3'));
      expect(m.inn.strikerId, 'A2');
      expect(m.inn.nonStrikerId, 'A3');
    });

    test('runs are not scored when caught or bowled', () {
      expect(
        () => m.apply(out(DismissalKind.caught, 'A1', runs: 1)),
        throwsIllegal(IllegalEventCode.invalidDelivery),
      );
    });
  });

  group('run out', () {
    test('runs completed count; the non-striker can be out', () {
      // One run completed, non-striker (A2, now at the striker's end) run
      // out going for the second without crossing.
      m = m.apply(out(DismissalKind.runOut, 'A2', runs: 1));
      expect(m.inn.runs, 1);
      expect(m.inn.batter('A1')!.runs, 1);
      expect(m.inn.batter('A2')!.status, BatterStatus.out);
      // After one run A1 is at the non-striker's end; A2's end is empty.
      expect(m.inn.strikerId, isNull);
      expect(m.inn.nonStrikerId, 'A1');
    });

    test('when the batters had crossed, the survivor keeps the far end', () {
      m = m.apply(
        const Delivery.wicket(
          Dismissal(kind: DismissalKind.runOut, batterId: 'A1', crossed: true),
        ),
      );
      // Crossed on the first run: A1 was heading to the far end and is out
      // there; A2 has reached the striker's end.
      expect(m.inn.strikerId, 'A2');
      expect(m.inn.nonStrikerId, isNull);
    });

    test('before the ball is bowled: no ball counted, not credited', () {
      m = m.apply(const RunOutBeforeDelivery('A2'));
      expect(m.inn.wickets, 1);
      expect(m.inn.legalBalls, 0);
      expect(m.inn.bowler('B11'), isNull);
      expect(m.inn.batter('A2')!.dismissal!.kind, DismissalKind.runOut);
      expect(
        () => started(MatchRules.t20).apply(const RunOutBeforeDelivery('A1')),
        throwsIllegal(IllegalEventCode.wrongBatterOut),
      );
    });

    test('a wicket after the winning run has been scored is refused', () {
      var chase =
          Match.start(setupFor(MatchRules.custom(overs: 1, playersPerSide: 3)))
              .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
              .apply(const BowlerSelected('B3'))
              .play(const [
                Delivery.four(),
                Delivery.dot(),
                Delivery.dot(),
                Delivery.dot(),
                Delivery.dot(),
                Delivery.dot(),
              ])
              .apply(const OpenersSelected(strikerId: 'B1', nonStrikerId: 'B2'))
              .apply(const BowlerSelected('A3'))
              .apply(const Delivery.runs(2));
      expect(chase.inn.runsRequired, 3);
      expect(
        () => chase.apply(out(DismissalKind.runOut, 'B1', runs: 3)),
        throwsIllegal(IllegalEventCode.invalidDelivery),
      );
      chase = chase.apply(out(DismissalKind.runOut, 'B1', runs: 2));
      expect(chase.inn.runs, 4);
      expect(chase.inn.wickets, 1);
    });
  });

  group('which batter', () {
    test('only the striker can be bowled, caught, LBW or stumped', () {
      expect(
        () => m.apply(out(DismissalKind.bowled, 'A2')),
        throwsIllegal(IllegalEventCode.wrongBatterOut),
      );
    });

    test('obstructing the field can be either batter', () {
      m = m.apply(out(DismissalKind.obstructingTheField, 'A2'));
      expect(m.inn.batter('A2')!.status, BatterStatus.out);
    });

    test('a batter not at the crease cannot be out', () {
      expect(
        () => m.apply(out(DismissalKind.runOut, 'A5')),
        throwsIllegal(IllegalEventCode.wrongBatterOut),
      );
    });

    test('the fielder must be on the fielding side', () {
      expect(
        () => m.apply(out(DismissalKind.caught, 'A1', fielder: 'A4')),
        throwsIllegal(IllegalEventCode.notInBowlingTeam),
      );
    });
  });

  group('extras and free hits limit dismissals', () {
    test('off a no-ball only run out, obstruction and hit twice', () {
      expect(m.allowedDismissals(DeliveryKind.noBall), {
        DismissalKind.runOut,
        DismissalKind.obstructingTheField,
        DismissalKind.hitTheBallTwice,
      });
      expect(
        () => m.apply(
          const Delivery.noBall(
            dismissal: Dismissal(kind: DismissalKind.caught, batterId: 'A1'),
          ),
        ),
        throwsIllegal(IllegalEventCode.dismissalNotAllowed),
      );
    });

    test('off a wide: stumped, hit wicket, run out, obstruction', () {
      expect(m.allowedDismissals(DeliveryKind.wide), {
        DismissalKind.stumped,
        DismissalKind.hitWicket,
        DismissalKind.runOut,
        DismissalKind.obstructingTheField,
      });
      m = m.apply(
        const Delivery(
          kind: DeliveryKind.wide,
          dismissal: Dismissal(kind: DismissalKind.stumped, batterId: 'A1'),
        ),
      );
      expect(m.inn.runs, 1);
      expect(m.inn.bowler('B11')!.wickets, 1);
      expect(m.inn.legalBalls, 0);
    });

    test('on a free hit the batter cannot be bowled or LBW', () {
      m = m.apply(const Delivery.noBall());
      expect(
        m.allowedDismissals(DeliveryKind.legal),
        isNot(contains(DismissalKind.bowled)),
      );
      expect(
        () => m.apply(out(DismissalKind.lbw, 'A1')),
        throwsIllegal(IllegalEventCode.dismissalNotAllowed),
      );
      m = m.apply(out(DismissalKind.runOut, 'A1'));
      expect(m.inn.wickets, 1);
    });

    test('LBW can be switched off', () {
      m = started(MatchRules.custom(overs: 5).copyWith(lbwAllowed: false));
      expect(
        () => m.apply(out(DismissalKind.lbw, 'A1')),
        throwsIllegal(IllegalEventCode.dismissalNotAllowed),
      );
    });
  });

  group('retirements and timed out', () {
    test('retired not out does not count as a wicket and may return', () {
      m = m.apply(const Delivery.four()).apply(const Retired('A1', out: false));
      expect(m.inn.wickets, 0);
      expect(m.inn.batter('A1')!.status, BatterStatus.retiredNotOut);
      final q = m.state.pending.single as ChooseBatter;
      expect(q.candidates.last, 'A1');
      m = m.apply(const BatterIn('A3')).apply(out(DismissalKind.bowled, 'A3'));
      m = m.apply(const BatterIn('A1'));
      expect(m.inn.batter('A1')!.status, BatterStatus.batting);
      expect(m.inn.batter('A1')!.runs, 4);
    });

    test('retired out counts as a wicket, not to the bowler', () {
      m = m.apply(const Retired('A2', out: true));
      expect(m.inn.wickets, 1);
      expect(m.inn.batter('A2')!.dismissal!.kind, DismissalKind.retiredOut);
    });

    test('timed out is a wicket for the incoming batter', () {
      m = m.apply(out(DismissalKind.bowled, 'A1')).apply(const TimedOut('A3'));
      expect(m.inn.wickets, 2);
      expect(m.inn.batter('A3')!.dismissal!.kind, DismissalKind.timedOut);
      expect((m.state.pending.single as ChooseBatter).suggested, 'A4');
    });

    test('junior rule: retire on reaching the set score', () {
      m = started(MatchRules.custom(overs: 10).copyWith(retireAtRuns: 10));
      m = m.play(const [Delivery.six(), Delivery.four()]);
      expect(m.inn.batter('A1')!.status, BatterStatus.retiredNotOut);
      expect(m.inn.wickets, 0);
      expect(m.state.pending.single, isA<ChooseBatter>());
    });
  });

  group('fall of wickets and partnerships', () {
    test('record the score and pair at each wicket', () {
      m = m.play([
        const Delivery.four(),
        const Delivery.runs(1),
        out(DismissalKind.bowled, 'A2'),
        const BatterIn('A3'),
        const Delivery.wide(),
      ]);
      expect(m.inn.fallOfWickets.single.runs, 5);
      expect(m.inn.fallOfWickets.single.batterId, 'A2');
      expect(m.inn.partnerships.first.runs, 5);
      expect(m.inn.partnerships.first.balls, 3);
      expect(m.inn.partnerships.last.batterIds, ['A3', 'A1']);
      expect(m.inn.partnerships.last.runs, 1);
      expect(m.inn.partnerships.last.balls, 0);
    });
  });
}
