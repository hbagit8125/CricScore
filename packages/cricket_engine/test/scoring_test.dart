import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late Match m;
  setUp(() => m = started(MatchRules.t20));

  group('runs off the bat', () {
    test('go to the striker, the team and the bowler', () {
      m = m.play(const [Delivery.four(), Delivery.six(), Delivery.runs(2)]);
      final a1 = m.inn.batter('A1')!;
      expect(m.inn.runs, 12);
      expect(a1.runs, 12);
      expect(a1.balls, 3);
      expect(a1.fours, 1);
      expect(a1.sixes, 1);
      expect(m.inn.bowler('B11')!.runs, 12);
      expect(m.inn.legalBalls, 3);
    });

    test('odd runs change ends, even runs and boundaries do not', () {
      m = m.apply(const Delivery.runs(2));
      expect(m.inn.strikerId, 'A1');
      m = m.apply(const Delivery.four());
      expect(m.inn.strikerId, 'A1');
      m = m.apply(const Delivery.runs(3));
      expect(m.inn.strikerId, 'A2');
    });

    test('runs completed before an overthrow boundary decide the strike', () {
      // One run completed, then the throw went for four: 5 runs, ends changed.
      m = m.apply(const Delivery(completedRuns: 1, boundary: 4));
      expect(m.inn.runs, 5);
      expect(m.inn.batter('A1')!.runs, 5);
      expect(m.inn.batter('A1')!.fours, 1);
      expect(m.inn.strikerId, 'A2');
    });
  });

  group('wides', () {
    test('add the penalty, are not a ball, and are not faced', () {
      m = m.apply(const Delivery.wide());
      expect(m.inn.runs, 1);
      expect(m.inn.extras.wides, 1);
      expect(m.inn.legalBalls, 0);
      expect(m.inn.batter('A1')!.balls, 0);
      expect(m.inn.bowler('B11')!.runs, 1);
      expect(m.inn.bowler('B11')!.wides, 1);
    });

    test('runs taken on a wide are all wides and change ends when odd', () {
      m = m.apply(const Delivery.wide(runs: 1));
      expect(m.inn.extras.wides, 2);
      expect(m.inn.strikerId, 'A2');
    });

    test('a wide to the boundary is five wides', () {
      m = m.apply(const Delivery.wide(boundary: true));
      expect(m.inn.extras.wides, 5);
      expect(m.inn.strikerId, 'A1');
    });

    test('cannot be byes, leg byes or six', () {
      expect(
        () => m.apply(
          const Delivery(kind: DeliveryKind.wide, runsTo: RunsTo.byes),
        ),
        throwsIllegal(IllegalEventCode.invalidDelivery),
      );
      expect(
        () => m.apply(const Delivery(kind: DeliveryKind.wide, boundary: 6)),
        throwsIllegal(IllegalEventCode.invalidDelivery),
      );
    });

    test('use the rules penalty value', () {
      m = started(MatchRules.custom(overs: 5).copyWith(wideRuns: 2));
      m = m.apply(const Delivery.wide());
      expect(m.inn.runs, 2);
    });
  });

  group('no-balls', () {
    test('penalty plus runs off the bat, faced but not a legal ball', () {
      m = m.apply(const Delivery.noBall(boundary: 4));
      expect(m.inn.runs, 5);
      expect(m.inn.extras.noBalls, 1);
      expect(m.inn.batter('A1')!.runs, 4);
      expect(m.inn.batter('A1')!.balls, 1);
      expect(m.inn.legalBalls, 0);
      expect(m.inn.bowler('B11')!.runs, 5);
      expect(m.inn.bowler('B11')!.noBalls, 1);
    });

    test('byes off a no-ball are byes, not charged to the bowler', () {
      m = m.apply(const Delivery.noBall(runsTo: RunsTo.byes, runs: 2));
      expect(m.inn.runs, 3);
      expect(m.inn.extras.byes, 2);
      expect(m.inn.extras.noBalls, 1);
      expect(m.inn.bowler('B11')!.runs, 1);
    });
  });

  group('byes and leg byes', () {
    test('count to the team and the ball but not the batter or bowler', () {
      m = m.play(const [Delivery.byes(1), Delivery.legByes(0, boundary: true)]);
      expect(m.inn.runs, 5);
      expect(m.inn.extras.byes, 1);
      expect(m.inn.extras.legByes, 4);
      expect(m.inn.batter('A1')!.runs, 0);
      expect(m.inn.batter('A1')!.balls, 1);
      expect(m.inn.batter('A2')!.balls, 1);
      expect(m.inn.bowler('B11')!.runs, 0);
      expect(m.inn.bowler('B11')!.dots, 2);
    });

    test('six can only come off the bat', () {
      expect(
        () => m.apply(const Delivery(runsTo: RunsTo.byes, boundary: 6)),
        throwsIllegal(IllegalEventCode.invalidDelivery),
      );
    });
  });

  group('overs', () {
    test('end after six legal balls, change ends, and need a new bowler', () {
      m = m.bowl(5).apply(const Delivery.wide()).apply(const Delivery.dot());
      expect(m.inn.oversText, '1.0');
      expect(m.inn.strikerId, 'A2');
      expect(m.inn.bowlerId, isNull);
      expect(m.state.pending.single, isA<ChooseBowler>());
      expect(
        () => m.apply(const Delivery.dot()),
        throwsIllegal(IllegalEventCode.bowlerNeeded),
      );
      expect(m.inn.overs.single.deliveries, hasLength(7));
    });

    test('a single off the last ball keeps the striker on strike', () {
      m = m.bowl(5).apply(const Delivery.runs(1));
      expect(m.inn.strikerId, 'A1');
    });

    test('a maiden allows byes but not wides', () {
      m = m.bowl(5).apply(const Delivery.byes(4));
      expect(m.inn.bowler('B11')!.maidens, 1);
      m = m
          .over('B10')
          .bowl(5)
          .apply(const Delivery.wide())
          .apply(const Delivery.dot());
      expect(m.inn.bowler('B10')!.maidens, 0);
      expect(m.inn.bowler('B11')!.figures(6), '1.0-1-0-0');
      expect(m.inn.bowler('B10')!.figures(6), '1.0-0-1-0');
    });

    test('an over the umpire calls early stands (Law 17.5)', () {
      m = m.bowl(5).apply(const OverCalledEarly());
      expect(m.inn.oversText, '0.5');
      expect(m.inn.bowlerId, isNull);
      expect(m.inn.strikerId, 'A2');
      expect(m.inn.ballsRemaining, 114);
      expect(
        () => started(MatchRules.t20).apply(const OverCalledEarly()),
        throwsIllegal(IllegalEventCode.notAllowedInFormat),
      );
    });

    test('an extra ball allowed by the umpire stands (Law 17.5)', () {
      m = m.bowl(6).apply(const OverExtended());
      expect(m.inn.bowlerId, 'B11');
      expect(m.inn.strikerId, 'A1');
      m = m.apply(const Delivery.runs(1));
      expect(m.inn.overs.single.isComplete, isTrue);
      expect(m.inn.legalBalls, 7);
      expect(m.inn.ballsRemaining, 114);
      // Quotas count overs: the seventh ball does not use up an over.
      expect(m.inn.bowler('B11')!.legalBalls, 7);
      m = m.over('B10').bowl(6).over('B11').bowl(6).over('B10').bowl(6);
      m = m.over('B11').bowl(6).over('B10').bowl(6).over('B11').bowl(6);
      expect(m.inn.bowler('B11')!.legalBalls, 25);
    });

    test('The Hundred changes ends every ten balls, not every five', () {
      m = started(MatchRules.hundred).bowl(5);
      expect(m.inn.oversText, '1.0');
      expect(m.inn.strikerId, 'A1');
      m = m.over('B11').bowl(5);
      expect(m.inn.strikerId, 'A2');
    });
  });

  group('rates', () {
    test('run rate uses legal balls; required rate counts what is left', () {
      m = m.play(const [Delivery.four(), Delivery.wide(), Delivery.runs(1)]);
      expect(m.inn.runRate, closeTo(18, 0.001));
      expect(m.inn.ballsRemaining, 118);
      expect(m.inn.target, isNull);
      expect(m.inn.requiredRunRate, isNull);
    });
  });

  group('free hit', () {
    test('follows a no-ball and carries over a wide', () {
      m = m.apply(const Delivery.noBall());
      expect(m.inn.freeHitNext, isTrue);
      m = m.apply(const Delivery.wide());
      expect(m.inn.freeHitNext, isTrue);
      m = m.apply(const Delivery.dot());
      expect(m.inn.freeHitNext, isFalse);
      final record = m.inn.currentOver!.deliveries;
      expect(record.map((d) => d.wasFreeHit), [false, true, true]);
    });

    test('is off when the rules have no free hits', () {
      m = started(MatchRules.custom(overs: 5)).apply(const Delivery.noBall());
      expect(m.inn.freeHitNext, isFalse);
    });
  });

  test('strike can be corrected manually', () {
    m = m.apply(const SwapStrike());
    expect(m.inn.strikerId, 'A2');
  });
}
