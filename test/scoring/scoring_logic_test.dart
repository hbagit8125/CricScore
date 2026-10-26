import 'package:cric_score/features/scoring/scoring_logic.dart';
import 'package:cricket_engine/cricket_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('deliveryFor', () {
    test('plain runs, fours and sixes', () {
      expect(deliveryFor(ArmedExtra.none, 0), const Delivery.dot());
      expect(deliveryFor(ArmedExtra.none, 3), const Delivery.runs(3));
      expect(deliveryFor(ArmedExtra.none, 4), const Delivery.four());
      expect(deliveryFor(ArmedExtra.none, 6), const Delivery.six());
      expect(deliveryFor(ArmedExtra.none, 5), const Delivery.runs(5));
    });

    test('wides: runs taken, and 4 for the boundary', () {
      expect(deliveryFor(ArmedExtra.wide, 0), const Delivery.wide());
      expect(deliveryFor(ArmedExtra.wide, 1), const Delivery.wide(runs: 1));
      expect(
        deliveryFor(ArmedExtra.wide, 4),
        const Delivery.wide(boundary: true),
      );
    });

    test('no-balls with bat runs, byes or leg byes', () {
      expect(
        deliveryFor(ArmedExtra.noBall, 6),
        const Delivery.noBall(boundary: 6),
      );
      expect(
        deliveryFor(ArmedExtra.noBallLegByes, 1),
        const Delivery.noBall(runsTo: RunsTo.legByes, runs: 1),
      );
    });

    test('byes and leg byes', () {
      expect(deliveryFor(ArmedExtra.byes, 2), const Delivery.byes(2));
      expect(
        deliveryFor(ArmedExtra.legByes, 4),
        const Delivery.legByes(0, boundary: true),
      );
    });

    test('a wicket ball never counts a boundary', () {
      const out = Dismissal(kind: DismissalKind.runOut, batterId: 'a');
      final d = deliveryFor(ArmedExtra.none, 4, dismissal: out);
      expect(d.completedRuns, 4);
      expect(d.boundary, 0);
    });
  });

  group('arming extras', () {
    test('tapping the same key disarms; byes combine with a no-ball', () {
      expect(ArmedExtra.none.toggle(ArmedExtra.wide), ArmedExtra.wide);
      expect(ArmedExtra.wide.toggle(ArmedExtra.wide), ArmedExtra.none);
      expect(ArmedExtra.wide.toggle(ArmedExtra.noBall), ArmedExtra.noBall);
      expect(ArmedExtra.noBall.toggle(ArmedExtra.byes), ArmedExtra.noBallByes);
      expect(ArmedExtra.noBallByes.toggle(ArmedExtra.byes), ArmedExtra.noBall);
    });

    test('six only off the bat, zero only when runs go to the batter', () {
      expect(ArmedExtra.byes.allowsSix, isFalse);
      expect(ArmedExtra.noBall.allowsSix, isTrue);
      expect(ArmedExtra.legByes.allowsZero, isFalse);
      expect(ArmedExtra.wide.allowsZero, isTrue);
    });
  });

  test('ball labels', () {
    const r = MatchRules.t20;
    expect(ballLabel(const Delivery.dot(), r), '•');
    expect(ballLabel(const Delivery.four(), r), '4');
    expect(ballLabel(const Delivery.wide(), r), 'wd');
    expect(ballLabel(const Delivery.wide(runs: 1), r), '2wd');
    expect(ballLabel(const Delivery.wide(boundary: true), r), '5wd');
    expect(ballLabel(const Delivery.noBall(boundary: 4), r), 'nb4');
    expect(ballLabel(const Delivery.noBall(), r), 'nb');
    expect(ballLabel(const Delivery.legByes(1), r), '1lb');
    const out = Dismissal(kind: DismissalKind.bowled, batterId: 'a');
    expect(ballLabel(const Delivery.wicket(out), r), 'W');
    expect(
      ballLabel(
        const Delivery.wicket(
          Dismissal(kind: DismissalKind.runOut, batterId: 'a'),
          runs: 1,
        ),
        r,
      ),
      '1 W',
    );
  });

  test('how out', () {
    String name(String id) => {'b': 'Shah', 'f': 'Ali'}[id]!;
    BatterCard out(DismissalKind k, {String? bowler, String? fielder}) =>
        BatterCard(
          playerId: 'x',
          position: 1,
          runs: 0,
          balls: 0,
          fours: 0,
          sixes: 0,
          status: BatterStatus.out,
          dismissal: DismissalRecord(
            kind: k,
            bowlerId: bowler,
            fielderId: fielder,
          ),
        );
    expect(howOut(out(DismissalKind.bowled, bowler: 'b'), name), 'b Shah');
    expect(
      howOut(out(DismissalKind.caught, bowler: 'b', fielder: 'f'), name),
      'c Ali b Shah',
    );
    expect(
      howOut(out(DismissalKind.caught, bowler: 'b', fielder: 'b'), name),
      'c & b Shah',
    );
    expect(
      howOut(out(DismissalKind.runOut, fielder: 'f'), name),
      'run out (Ali)',
    );
  });
}
