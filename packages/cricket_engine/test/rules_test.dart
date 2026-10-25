import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  group('presets', () {
    int? quota(MatchRules r, [int? balls]) => r.bowlerLimit.maxBalls(
      inningsBalls: balls ?? r.ballsPerInnings,
      ballsPerOver: r.ballsPerOver,
    );

    test('T20 is 20 overs with 4 overs per bowler and free hits', () {
      expect(MatchRules.t20.ballsPerInnings, 120);
      expect(quota(MatchRules.t20), 24);
      expect(MatchRules.t20.freeHitAfterNoBall, isTrue);
      expect(MatchRules.t20.tieBreak, TieBreak.superOverRepeat);
    });

    test('ODI allows 10 overs per bowler', () {
      expect(MatchRules.odi.ballsPerInnings, 300);
      expect(quota(MatchRules.odi), 60);
    });

    test('T10 allows 2 overs per bowler', () {
      expect(quota(MatchRules.t10), 12);
    });

    test('The Hundred is 100 balls in fives, 20 balls per bowler', () {
      expect(MatchRules.hundred.ballsPerOver, 5);
      expect(MatchRules.hundred.ballsPerInnings, 100);
      expect(quota(MatchRules.hundred), 20);
    });

    test('a fifth of a reduced innings rounds up to whole overs', () {
      // 7 overs: 7 / 5 rounds up to 2 overs.
      expect(quota(MatchRules.t20, 42), 12);
      // 3 overs: still at least 1 over each.
      expect(quota(MatchRules.t20, 18), 6);
    });

    test('custom rules take overs and team size', () {
      final r = MatchRules.custom(overs: 8, playersPerSide: 6);
      expect(r.ballsPerInnings, 48);
      expect(r.playersPerSide, 6);
      expect(r.maxWickets, 5);
    });

    test('last batter alone allows one more wicket', () {
      final r = MatchRules.custom(
        overs: 5,
      ).copyWith(lastBatterCanBatAlone: true);
      expect(r.maxWickets, 11);
    });
  });

  group('validation', () {
    test('presets are valid', () {
      for (final r in MatchRules.presets) {
        expect(r.validate(), isEmpty, reason: r.name);
      }
    });

    test('rejects impossible rules', () {
      final r = MatchRules.t20.copyWith(playersPerSide: 1, ballsPerOver: 0);
      expect(r.validate(), hasLength(2));
    });

    test('rejects a team of the wrong size', () {
      final setup = setupFor(MatchRules.t20);
      final short = MatchSetup(
        rules: setup.rules,
        teamA: TeamSheet(
          id: 'LIO',
          name: 'Lions',
          players: setup.teamA.players.take(10).toList(),
        ),
        teamB: setup.teamB,
        toss: setup.toss,
      );
      expect(short.validate().single, contains('has 10 players'));
      expect(
        () => Match.start(short),
        throwsIllegal(IllegalEventCode.invalidSetup),
      );
    });

    test('rejects duplicate names and ids', () {
      final setup = setupFor(MatchRules.custom(overs: 5, playersPerSide: 2));
      final dup = MatchSetup(
        rules: setup.rules,
        teamA: TeamSheet(
          id: 'LIO',
          name: 'Lions',
          players: const [
            PlayerRef(id: 'X', name: 'Sam'),
            PlayerRef(id: 'Y', name: 'sam '),
          ],
        ),
        teamB: TeamSheet(
          id: 'TIG',
          name: 'Tigers',
          players: const [
            PlayerRef(id: 'X', name: 'Ali'),
            PlayerRef(id: 'Z', name: 'Raza'),
          ],
        ),
        toss: setup.toss,
      );
      final problems = dup.validate();
      expect(problems, contains('Lions has two players called sam.'));
      expect(
        problems,
        contains('Every player needs a unique id across both teams.'),
      );
    });

    test('toss decides who bats first', () {
      expect(setupFor(MatchRules.t20).battingFirstTeamId, 'LIO');
      expect(
        setupFor(MatchRules.t20, lionsBatFirst: false).battingFirstTeamId,
        'TIG',
      );
    });
  });
}
