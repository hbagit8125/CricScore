import '../rules/match_rules.dart';
import 'team.dart';

enum TossDecision { bat, bowl }

final class Toss {
  const Toss({required this.wonByTeamId, required this.decision});

  final String wonByTeamId;
  final TossDecision decision;
}

/// Everything fixed before the first ball: rules, teams and toss.
final class MatchSetup {
  const MatchSetup({
    required this.rules,
    required this.teamA,
    required this.teamB,
    required this.toss,
  });

  final MatchRules rules;
  final TeamSheet teamA;
  final TeamSheet teamB;
  final Toss toss;

  TeamSheet team(String teamId) => teamId == teamA.id ? teamA : teamB;

  TeamSheet opponent(String teamId) => teamId == teamA.id ? teamB : teamA;

  /// The side that bats first, decided by the toss.
  String get battingFirstTeamId {
    final winner = toss.wonByTeamId;
    return toss.decision == TossDecision.bat ? winner : opponent(winner).id;
  }

  /// Problems that make this setup unusable, empty when valid.
  List<String> validate() {
    final problems = [...rules.validate()];
    if (teamA.id == teamB.id) problems.add('The two teams need different ids.');
    if (toss.wonByTeamId != teamA.id && toss.wonByTeamId != teamB.id) {
      problems.add('The toss winner must be one of the two teams.');
    }
    for (final team in [teamA, teamB]) {
      if (team.players.length != rules.playersPerSide) {
        problems.add(
          '${team.name} has ${team.players.length} players; '
          '${rules.name} needs ${rules.playersPerSide}.',
        );
      }
      final names = <String>{};
      for (final p in team.squad) {
        if (p.name.trim().isEmpty) {
          problems.add('${team.name} has a player with no name.');
        }
        if (!names.add(p.name.trim().toLowerCase())) {
          problems.add('${team.name} has two players called ${p.name.trim()}.');
        }
      }
    }
    final ids = [...teamA.squad, ...teamB.squad].map((p) => p.id).toList();
    if (ids.toSet().length != ids.length) {
      problems.add('Every player needs a unique id across both teams.');
    }
    return problems;
  }
}
