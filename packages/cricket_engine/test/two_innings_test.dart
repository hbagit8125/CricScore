import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// Three-a-side Test rules keep innings short: two wickets is all out.
final rules = MatchRules.test.copyWith(playersPerSide: 3, followOnMargin: 10);

const lions = 'LIO';
const tigers = 'TIG';

/// Bats out the current innings: [runs] in singles-free boundaries and
/// threes, then two wickets. Handles openers and bowler changes.
Match batInnings(Match m, int runs, {bool declare = false}) {
  final inn = m.inn;
  final batting = inn.battingTeamId == lions ? 'A' : 'B';
  final bowling = inn.battingTeamId == lions ? 'B' : 'A';
  m = m.apply(
    OpenersSelected(strikerId: '${batting}1', nonStrikerId: '${batting}2'),
  );
  var bowler = 0;
  void nextBowler() {
    bowler = bowler == 3 ? 2 : 3;
    m = m.apply(BowlerSelected('$bowling$bowler'));
  }

  nextBowler();
  var scored = 0;
  while (scored < runs) {
    final d = runs - scored >= 4
        ? const Delivery.four()
        : Delivery.runs(
            runs - scored == 3
                ? 2
                : (runs - scored).isEven
                ? 2
                : 1,
          );
    m = m.apply(d);
    scored += d.runs;
    if (m.state.isComplete) break;
    if (m.state.pending.whereType<ChooseBowler>().isNotEmpty) nextBowler();
  }
  if (m.state.isComplete) return m;
  if (declare) return m.apply(const Declare());
  for (var w = 0; w < 2; w++) {
    final striker = m.inn.strikerId!;
    m = m.apply(
      Delivery.wicket(Dismissal(kind: DismissalKind.bowled, batterId: striker)),
    );
    if (m.state.isComplete || m.inn.number != inn.number) break;
    if (m.state.pending.whereType<ChooseBatter>().isNotEmpty) {
      m = m.apply(
        BatterIn(m.state.pending.whereType<ChooseBatter>().single.suggested),
      );
    }
    if (m.state.pending.whereType<ChooseBowler>().isNotEmpty) nextBowler();
  }
  return m;
}

Match newTest([MatchRules? r]) => Match.start(setupFor(r ?? rules));

void main() {
  test('presets', () {
    expect(MatchRules.test.isTwoInnings, isTrue);
    expect(MatchRules.test.followOnMargin, 200);
    expect(MatchRules.firstClass.followOnMargin, 150);
    expect(MatchRules.followOnMarginForDays(5), 200);
    expect(MatchRules.followOnMarginForDays(4), 150);
    expect(MatchRules.followOnMarginForDays(2), 100);
    expect(MatchRules.followOnMarginForDays(1), 75);
    expect(
      MatchRules.test.copyWith(tieBreak: TieBreak.superOverRepeat).validate(),
      isNotEmpty,
    );
  });

  test('innings alternate and the fourth has a target', () {
    var m = batInnings(newTest(), 20);
    expect(m.inn.battingTeamId, tigers);
    expect(m.inn.target, isNull);
    m = batInnings(m, 15);
    expect(m.inn.battingTeamId, lions);
    m = batInnings(m, 12);
    expect(m.inn.battingTeamId, tigers);
    // Lions 32, Tigers 15: Tigers need 18.
    expect(m.inn.target, 18);
    m = batInnings(m, 18);
    final r = m.state.result as Win;
    expect(r.winnerTeamId, tigers);
    expect(r.describe(m.setup), 'Tigers won by 2 wickets');
  });

  test('side batting last falls short: defeat by runs', () {
    var m = batInnings(newTest(), 20);
    m = batInnings(batInnings(batInnings(m, 15), 12), 10);
    expect((m.state.result as Win).describe(m.setup), 'Lions won by 7 runs');
  });

  test('scores level with the last side all out is a tie', () {
    var m = batInnings(newTest(), 20);
    m = batInnings(batInnings(batInnings(m, 15), 12), 17);
    expect(m.state.result, isA<Tie>());
  });

  group('follow-on (Law 14)', () {
    test('offered when the lead reaches the margin', () {
      final m = batInnings(batInnings(newTest(), 30), 12);
      final q = m.state.pending.single as ChooseFollowOn;
      expect(q.leadingTeamId, lions);
      expect(q.trailingTeamId, tigers);
      expect(q.lead, 18);
      expect(
        () =>
            m.apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2')),
        throwsIllegal(IllegalEventCode.followOnPending),
      );
    });

    test('not offered below the margin', () {
      final m = batInnings(batInnings(newTest(), 30), 21);
      expect(m.state.pending.first, isA<ChooseOpeners>());
      expect(m.inn.battingTeamId, lions);
    });

    test(
      'enforced: the trailing side bats again and can lose by an innings',
      () {
        var m = batInnings(
          batInnings(newTest(), 30),
          12,
        ).apply(const FollowOn(enforce: true));
        expect(m.inn.battingTeamId, tigers);
        m = batInnings(m, 10);
        final r = m.state.result as Win;
        expect(r.winnerTeamId, lions);
        expect(r.describe(m.setup), 'Lions won by an innings and 8 runs');
      },
    );

    test('enforced but the trailing side sets a target', () {
      var m = batInnings(
        batInnings(newTest(), 30),
        12,
      ).apply(const FollowOn(enforce: true));
      m = batInnings(m, 25);
      expect(m.inn.battingTeamId, lions);
      expect(m.inn.target, 8);
    });

    test('a margin reduced for lost time makes it available (Law 14.1.3)', () {
      var m = batInnings(newTest(), 30).apply(const FollowOnMarginSet(5));
      m = batInnings(m, 24);
      expect((m.state.pending.single as ChooseFollowOn).lead, 6);
      expect(
        () => m.apply(const FollowOnMarginSet(1)),
        throwsIllegal(IllegalEventCode.followOnPending),
      );
    });

    test('declined: the leading side bats again', () {
      final m = batInnings(
        batInnings(newTest(), 30),
        12,
      ).apply(const FollowOn(enforce: false));
      expect(m.inn.battingTeamId, lions);
    });

    test('cannot be chosen when it is not available', () {
      expect(
        () => newTest().apply(const FollowOn(enforce: true)),
        throwsIllegal(IllegalEventCode.notAllowedInFormat),
      );
    });
  });

  group('declarations and forfeits (Law 15)', () {
    test('a declaration closes the innings', () {
      final m = batInnings(newTest(), 40, declare: true);
      expect(m.state.innings.first.endReason, InningsEndReason.declared);
      expect(m.state.innings.first.runs, 40);
      expect(m.inn.battingTeamId, tigers);
    });

    test('a forfeited innings counts as completed with no runs', () {
      var m = batInnings(newTest(), 20);
      m = batInnings(m, 15).apply(const Forfeit());
      expect(m.state.innings[2].endReason, InningsEndReason.forfeited);
      expect(m.inn.battingTeamId, tigers);
      expect(m.inn.target, 6);
    });

    test('forfeit only before the innings starts', () {
      final m = newTest().apply(
        const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'),
      );
      expect(
        () => m.apply(const Forfeit()),
        throwsIllegal(IllegalEventCode.notAllowedInFormat),
      );
    });

    test('limited-overs matches cannot declare, forfeit or draw', () {
      final m = started(MatchRules.t20);
      for (final e in const [Declare(), Forfeit(), Drawn()]) {
        expect(
          () => m.apply(e),
          throwsIllegal(IllegalEventCode.notAllowedInFormat),
        );
      }
    });
  });

  test('a draw ends the match when time runs out', () {
    final m = batInnings(newTest(), 20).apply(const Drawn());
    expect(m.state.result, isA<Draw>());
    expect(m.state.result!.describe(m.setup), 'Match drawn');
    expect(m.state.pending, isEmpty);
  });

  test('Tests have no revised targets', () {
    expect(
      () => newTest().apply(const RevisedTarget(target: 100)),
      throwsIllegal(IllegalEventCode.notAllowedInFormat),
    );
  });

  group('penalty runs (Law 41)', () {
    test('to the batting side go to the innings in progress', () {
      final m = started(MatchRules.t20).apply(const PenaltyRuns(teamId: lions));
      expect(m.inn.runs, 5);
      expect(m.inn.extras.penalty, 5);
      expect(m.inn.legalBalls, 0);
      expect(m.inn.bowler('B11'), isNull);
    });

    test('to a side yet to bat go to its next innings', () {
      final m = started(MatchRules.custom(overs: 1, playersPerSide: 3))
          .apply(const PenaltyRuns(teamId: tigers))
          .bowl(6, const Delivery.runs(2));
      expect(m.inn.battingTeamId, tigers);
      expect(m.inn.runs, 5);
      expect(m.inn.extras.penalty, 5);
      expect(m.inn.target, 13);
    });

    test('to the fielding side go to its last completed innings and '
        'raise the target', () {
      var m = batInnings(batInnings(batInnings(newTest(), 20), 15), 12);
      expect(m.inn.target, 18);
      m = m.apply(const PenaltyRuns(teamId: lions));
      expect(m.state.innings[2].runs, 17);
      expect(m.state.innings[2].extras.penalty, 5);
      expect(m.inn.target, 23);
    });

    test('can win a match', () {
      var m = batInnings(batInnings(batInnings(newTest(), 20), 15), 12);
      m = m
          .apply(const OpenersSelected(strikerId: 'B1', nonStrikerId: 'B2'))
          .apply(const BowlerSelected('A3'))
          .play(const [
            Delivery.four(),
            Delivery.four(),
            Delivery.four(),
            Delivery.runs(1),
          ]);
      expect(m.inn.runsRequired, 5);
      m = m.apply(const PenaltyRuns(teamId: tigers));
      expect((m.state.result as Win).winnerTeamId, tigers);
    });

    test('must be positive', () {
      expect(
        () => started(
          MatchRules.t20,
        ).apply(const PenaltyRuns(teamId: lions, runs: 0)),
        throwsIllegal(IllegalEventCode.invalidPenalty),
      );
    });
  });

  group('substitutions', () {
    test('the replaced player can no longer bat; the substitute can', () {
      var m = started(MatchRules.t20).apply(
        const Substitute(
          outPlayerId: 'A3',
          inPlayerId: 'AS',
          reason: SubstitutionReason.concussion,
        ),
      );
      m = m.apply(
        const Delivery.wicket(
          Dismissal(kind: DismissalKind.bowled, batterId: 'A1'),
        ),
      );
      final q = m.state.pending.single as ChooseBatter;
      expect(q.candidates, isNot(contains('A3')));
      expect(q.suggested, 'AS', reason: 'takes the replaced player\'s place');
      expect(
        m.state.substitutions.single.reason,
        SubstitutionReason.concussion,
      );
    });

    test('the replaced player can no longer bowl; the substitute can', () {
      var m = started(MatchRules.t20).apply(
        const Substitute(
          outPlayerId: 'B10',
          inPlayerId: 'BS',
          reason: SubstitutionReason.impactPlayer,
        ),
      );
      m = m.bowl(6);
      final q = m.state.pending.single as ChooseBowler;
      expect(q.eligible, contains('BS'));
      expect(q.eligible, isNot(contains('B10')));
      expect(
        () => m.over('B10'),
        throwsIllegal(IllegalEventCode.notInBowlingTeam),
      );
    });

    test('substitute fielders may take catches', () {
      final m = started(MatchRules.t20).apply(
        const Delivery.wicket(
          Dismissal(
            kind: DismissalKind.caught,
            batterId: 'A1',
            fielderId: 'BS',
          ),
        ),
      );
      expect(m.inn.batter('A1')!.dismissal!.fielderId, 'BS');
    });

    test(
      'refused for players at the crease, the bowler, unknown or used subs',
      () {
        final m = started(MatchRules.t20);
        Matcher refused() =>
            throwsIllegal(IllegalEventCode.invalidSubstitution);
        expect(
          () => m.apply(
            const Substitute(
              outPlayerId: 'A1',
              inPlayerId: 'AS',
              reason: SubstitutionReason.other,
            ),
          ),
          refused(),
        );
        expect(
          () => m.apply(
            const Substitute(
              outPlayerId: 'B11',
              inPlayerId: 'BS',
              reason: SubstitutionReason.other,
            ),
          ),
          refused(),
        );
        expect(
          () => m.apply(
            const Substitute(
              outPlayerId: 'A5',
              inPlayerId: 'BS',
              reason: SubstitutionReason.other,
            ),
          ),
          refused(),
        );
        final once = m.apply(
          const Substitute(
            outPlayerId: 'A5',
            inPlayerId: 'AS',
            reason: SubstitutionReason.other,
          ),
        );
        expect(
          () => once.apply(
            const Substitute(
              outPlayerId: 'A6',
              inPlayerId: 'AS',
              reason: SubstitutionReason.other,
            ),
          ),
          refused(),
        );
        expect(
          () => once.apply(
            const Substitute(
              outPlayerId: 'A5',
              inPlayerId: 'AS',
              reason: SubstitutionReason.other,
            ),
          ),
          refused(),
        );
      },
    );
  });
}
