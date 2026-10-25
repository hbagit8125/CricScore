import '../model/match_setup.dart';

sealed class MatchResult {
  const MatchResult();

  /// "Lions won by 6 wickets (4 balls left)"
  String describe(MatchSetup setup);
}

sealed class WinMargin {
  const WinMargin();
}

final class ByRuns extends WinMargin {
  const ByRuns(this.runs);

  final int runs;
}

final class ByWickets extends WinMargin {
  const ByWickets(this.wickets, {this.ballsRemaining});

  final int wickets;

  /// Null when the innings had no ball limit.
  final int? ballsRemaining;
}

/// Won the super over (or the last of several).
final class BySuperOver extends WinMargin {
  const BySuperOver();
}

/// Super over tied; won on boundaries across the match.
final class ByBoundaryCount extends WinMargin {
  const ByBoundaryCount({required this.winner, required this.loser});

  final int winner;
  final int loser;
}

final class Win extends MatchResult {
  const Win({
    required this.winnerTeamId,
    required this.margin,
    this.revisedTarget = false,
  });

  final String winnerTeamId;
  final WinMargin margin;

  /// The chase had a revised target, e.g. from DLS.
  final bool revisedTarget;

  @override
  String describe(MatchSetup setup) {
    final name = setup.team(winnerTeamId).name;
    final text = switch (margin) {
      ByRuns(:final runs) => 'won by $runs ${runs == 1 ? 'run' : 'runs'}',
      ByWickets(:final wickets, :final ballsRemaining) =>
        'won by $wickets ${wickets == 1 ? 'wicket' : 'wickets'}'
            '${ballsRemaining == null || ballsRemaining == 0 ? '' : ' ($ballsRemaining ${ballsRemaining == 1 ? 'ball' : 'balls'} left)'}',
      BySuperOver() => 'won the super over',
      ByBoundaryCount(:final winner, :final loser) =>
        'won on boundary count ($winner to $loser)',
    };
    return '$name $text${revisedTarget ? ' (revised target)' : ''}';
  }
}

final class Tie extends MatchResult {
  const Tie();

  @override
  String describe(MatchSetup setup) => 'Match tied';
}

final class NoResult extends MatchResult {
  const NoResult();

  @override
  String describe(MatchSetup setup) => 'No result';
}
