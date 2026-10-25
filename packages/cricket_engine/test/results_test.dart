import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// One-over, three-a-side games keep these scenarios short.
final oneOver = MatchRules.custom(overs: 1, playersPerSide: 3);

Match firstInnings(MatchRules rules, List<Delivery> balls) {
  var m = Match.start(setupFor(rules))
      .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
      .apply(BowlerSelected('B${rules.playersPerSide}'));
  for (final b in balls) {
    m = m.apply(b);
  }
  return m;
}

Match startChase(Match m) => m
    .apply(const OpenersSelected(strikerId: 'B1', nonStrikerId: 'B2'))
    .apply(BowlerSelected('A${m.setup.rules.playersPerSide}'));

void main() {
  test('first innings ends after the overs and sets the target', () {
    final m = firstInnings(oneOver, [
      const Delivery.four(),
      ...List.filled(5, const Delivery.dot()),
    ]);
    expect(m.state.innings.first.endReason, InningsEndReason.ballsComplete);
    expect(m.state.innings.first.batters.first.status, BatterStatus.notOut);
    expect(m.inn.number, 2);
    expect(m.inn.battingTeamId, 'TIG');
    expect(m.inn.target, 5);
    expect(m.state.pending.first, isA<ChooseOpeners>());
  });

  test('chasing side wins by wickets with balls left', () {
    var m = startChase(
      firstInnings(oneOver, List.filled(6, const Delivery.runs(1))),
    );
    m = m.play(const [Delivery.four(), Delivery.runs(3)]);
    final result = m.state.result as Win;
    expect(result.winnerTeamId, 'TIG');
    expect((result.margin as ByWickets).wickets, 2);
    expect((result.margin as ByWickets).ballsRemaining, 4);
    expect(m.inn.endReason, InningsEndReason.targetReached);
    expect(result.describe(m.setup), 'Tigers won by 2 wickets (4 balls left)');
  });

  test('defending side wins by runs', () {
    var m = startChase(
      firstInnings(oneOver, List.filled(6, const Delivery.runs(2))),
    );
    m = m.bowl(6, const Delivery.runs(1));
    final result = m.state.result as Win;
    expect(result.winnerTeamId, 'LIO');
    expect((result.margin as ByRuns).runs, 6);
    expect(result.describe(m.setup), 'Lions won by 6 runs');
  });

  test('all out ends the innings; one run short is a defeat by 1 run', () {
    var m = startChase(
      firstInnings(oneOver, [
        const Delivery.runs(2),
        ...List.filled(5, const Delivery.dot()),
      ]),
    );
    // B1 takes a single, so B2 faces and is bowled.
    m = m.play(const [
      Delivery.runs(1),
      Delivery.wicket(Dismissal(kind: DismissalKind.bowled, batterId: 'B2')),
    ]);
    expect(m.state.result, isNull);
    m = m
        .apply(const BatterIn('B3'))
        .apply(
          const Delivery.wicket(
            Dismissal(kind: DismissalKind.bowled, batterId: 'B3'),
          ),
        );
    expect(m.state.innings[1].endReason, InningsEndReason.allOut);
    expect((m.state.result as Win).describe(m.setup), 'Lions won by 1 run');
  });

  test('level scores without a tie-break is a tie', () {
    var m = startChase(
      firstInnings(oneOver, List.filled(6, const Delivery.runs(1))),
    );
    m = m.bowl(6, const Delivery.runs(1));
    expect(m.state.result, isA<Tie>());
    expect(m.state.result!.describe(m.setup), 'Match tied');
  });

  group('super over', () {
    final rules = oneOver.copyWith(tieBreak: TieBreak.superOverRepeat);

    Match tied() {
      final m = startChase(
        firstInnings(rules, List.filled(6, const Delivery.runs(1))),
      );
      return m.bowl(6, const Delivery.runs(1));
    }

    test('a tie starts a super over, side batting second goes first', () {
      final m = tied();
      expect(m.state.result, isNull);
      expect(m.inn.kind, InningsKind.superOver);
      expect(m.inn.battingTeamId, 'TIG');
      expect(m.inn.ballLimit, 6);
      expect(m.inn.maxWickets, 2);
    });

    test('the side chasing in the super over can win it', () {
      var m = tied()
          .apply(const OpenersSelected(strikerId: 'B1', nonStrikerId: 'B2'))
          .apply(const BowlerSelected('A3'))
          .bowl(6, const Delivery.runs(1));
      expect(m.inn.target, 7);
      m = m
          .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
          .apply(const BowlerSelected('B3'))
          .play(const [Delivery.six(), Delivery.runs(1)]);
      final r = m.state.result as Win;
      expect(r.winnerTeamId, 'LIO');
      expect(r.describe(m.setup), 'Lions won the super over');
    });

    test('a tied super over is repeated with the other side batting first; '
        'dismissed batters and the previous bowler are barred', () {
      var m = tied()
          .apply(const OpenersSelected(strikerId: 'B1', nonStrikerId: 'B2'))
          .apply(const BowlerSelected('A3'))
          .apply(
            const Delivery.wicket(
              Dismissal(kind: DismissalKind.bowled, batterId: 'B1'),
            ),
          )
          .apply(const BatterIn('B3'))
          .bowl(5, const Delivery.dot())
          .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
          .apply(const BowlerSelected('B3'))
          .bowl(6, const Delivery.dot());
      expect(m.state.result, isNull);
      expect(m.inn.kind, InningsKind.superOver);
      expect(m.inn.battingTeamId, 'LIO');
      // Tigers' bowler B3 from the last super over cannot bowl again.
      m = m.apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'));
      final q = m.state.pending.single as ChooseBowler;
      expect(q.ineligible['B3'], BowlerIneligibility.bowledPreviousSuperOver);
      m = m.over('B2').bowl(6, const Delivery.dot());
      // Tigers' B1 was dismissed in the last super over and cannot bat.
      final openers = m.state.pending.first as ChooseOpeners;
      expect(openers.candidates, isNot(contains('B1')));
    });

    test(
      'boundary count-back decides a tied super over under the old rule',
      () {
        final old = oneOver.copyWith(
          tieBreak: TieBreak.superOverThenBoundaryCount,
        );
        var m = startChase(
          firstInnings(old, [
            const Delivery.four(),
            ...List.filled(5, const Delivery.dot()),
          ]),
        );
        m = m.bowl(5, const Delivery.dot()).apply(const Delivery.runs(4));
        expect(m.inn.kind, InningsKind.superOver);
        m = m
            .apply(const OpenersSelected(strikerId: 'B1', nonStrikerId: 'B2'))
            .apply(const BowlerSelected('A3'))
            .bowl(6, const Delivery.dot())
            .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
            .apply(const BowlerSelected('B3'))
            .bowl(6, const Delivery.dot());
        final r = m.state.result as Win;
        expect(r.winnerTeamId, 'LIO');
        expect(r.describe(m.setup), 'Lions won on boundary count (1 to 0)');
      },
    );
  });

  group('revised targets', () {
    test('a revised target and overs decide the chase', () {
      var m = startChase(
        firstInnings(oneOver, List.filled(6, const Delivery.runs(2))),
      );
      m = m.apply(const RevisedTarget(ballsPerInnings: 3, target: 8));
      expect(m.inn.ballLimit, 3);
      expect(m.inn.target, 8);
      m = m.play(const [Delivery.four(), Delivery.dot(), Delivery.runs(2)]);
      final r = m.state.result as Win;
      expect(r.winnerTeamId, 'LIO');
      expect((r.margin as ByRuns).runs, 1);
      expect(r.describe(m.setup), 'Lions won by 1 run (revised target)');
    });

    test('cannot cut an innings below the balls already bowled', () {
      final m = firstInnings(
        MatchRules.t20,
        List.filled(4, const Delivery.dot()),
      );
      expect(
        () => m.apply(const RevisedTarget(ballsPerInnings: 3)),
        throwsIllegal(IllegalEventCode.invalidRevision),
      );
    });

    test('a first-innings target is refused', () {
      final m = firstInnings(MatchRules.t20, const []);
      expect(
        () => m.apply(const RevisedTarget(target: 100)),
        throwsIllegal(IllegalEventCode.invalidRevision),
      );
    });

    test('shortening the first innings ends it if the overs are used up', () {
      var m = firstInnings(
        MatchRules.t20,
        List.filled(6, const Delivery.runs(1)),
      );
      m = m.apply(const RevisedTarget(ballsPerInnings: 6));
      expect(m.inn.number, 2);
      expect(m.inn.ballLimit, 6);
      expect(m.inn.target, 7);
    });
  });

  group('other endings', () {
    test('abandoned match has no result and accepts no more events', () {
      final m = firstInnings(MatchRules.t20, const [
        Delivery.four(),
      ]).apply(const Abandoned());
      expect(m.state.result, isA<NoResult>());
      expect(m.state.pending, isEmpty);
      expect(
        () => m.apply(const Delivery.dot()),
        throwsIllegal(IllegalEventCode.matchOver),
      );
    });

    test('the scorer can close an innings', () {
      final m = firstInnings(MatchRules.t20, const [
        Delivery.four(),
      ]).apply(const EndInnings());
      expect(m.state.innings.first.endReason, InningsEndReason.closed);
      expect(m.inn.target, 5);
    });

    test('last batter can bat alone when the rules allow it', () {
      final rules = oneOver.copyWith(lastBatterCanBatAlone: true);
      var m = firstInnings(rules, const [
        Delivery.wicket(Dismissal(kind: DismissalKind.bowled, batterId: 'A1')),
      ]);
      m = m
          .apply(const BatterIn('A3'))
          .apply(
            const Delivery.wicket(
              Dismissal(kind: DismissalKind.bowled, batterId: 'A3'),
            ),
          );
      expect(m.inn.strikerId, 'A2');
      expect(m.inn.nonStrikerId, isNull);
      expect(m.state.pending, isEmpty);
      m = m.apply(const Delivery.runs(1));
      expect(m.inn.strikerId, 'A2', reason: 'a lone batter keeps the strike');
      m = m.apply(
        const Delivery.wicket(
          Dismissal(kind: DismissalKind.bowled, batterId: 'A2'),
        ),
      );
      expect(m.state.innings.first.endReason, InningsEndReason.allOut);
      expect(m.state.innings.first.wickets, 3);
    });

    test('without that rule the innings ends at players minus one', () {
      var m = firstInnings(oneOver, const [
        Delivery.wicket(Dismissal(kind: DismissalKind.bowled, batterId: 'A1')),
      ]);
      m = m
          .apply(const BatterIn('A3'))
          .apply(
            const Delivery.wicket(
              Dismissal(kind: DismissalKind.bowled, batterId: 'A3'),
            ),
          );
      expect(m.state.innings.first.endReason, InningsEndReason.allOut);
    });
  });
}
