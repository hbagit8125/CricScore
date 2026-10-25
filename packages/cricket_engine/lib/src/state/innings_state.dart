import 'cards.dart';

enum InningsKind { regular, superOver }

enum InningsEndReason {
  allOut,
  ballsComplete,
  targetReached,
  declared,
  forfeited,

  /// Closed by the scorer, or by the end of the match.
  closed,
}

/// A read-only view of one innings.
final class InningsState {
  const InningsState({
    required this.number,
    required this.kind,
    required this.battingTeamId,
    required this.bowlingTeamId,
    required this.ballsPerOver,
    required this.runs,
    required this.wickets,
    required this.legalBalls,
    required this.ballLimit,
    required this.maxWickets,
    required this.bowlerMaxBalls,
    required this.target,
    required this.extras,
    required this.batters,
    required this.bowlers,
    required this.fallOfWickets,
    required this.partnerships,
    required this.overs,
    required this.strikerId,
    required this.nonStrikerId,
    required this.bowlerId,
    required this.freeHitNext,
    required this.endReason,
  });

  /// 1 for the first innings of the match, counting super overs.
  final int number;
  final InningsKind kind;
  final String battingTeamId;
  final String bowlingTeamId;
  final int ballsPerOver;
  final int runs;
  final int wickets;
  final int legalBalls;

  /// Legal balls allowed, or null for no limit.
  final int? ballLimit;
  final int maxWickets;

  /// Legal balls one bowler may bowl, or null for no limit.
  final int? bowlerMaxBalls;

  /// Runs needed to win, when chasing.
  final int? target;
  final Extras extras;

  /// In order of coming in.
  final List<BatterCard> batters;

  /// In order of first bowling.
  final List<BowlerCard> bowlers;
  final List<FallOfWicket> fallOfWickets;
  final List<Partnership> partnerships;

  /// Completed overs and the one in progress, if any.
  final List<OverSummary> overs;

  /// Null when that end is vacant.
  final String? strikerId;
  final String? nonStrikerId;

  /// Null between overs until the next bowler is chosen.
  final String? bowlerId;

  /// The next delivery is a free hit.
  final bool freeHitNext;

  /// Null while the innings is open.
  final InningsEndReason? endReason;

  bool get isClosed => endReason != null;

  String get oversText => formatOvers(legalBalls, ballsPerOver);

  double get runRate => legalBalls == 0 ? 0 : runs * ballsPerOver / legalBalls;

  int? get ballsRemaining => ballLimit == null ? null : ballLimit! - legalBalls;

  int? get runsRequired => target == null ? null : target! - runs;

  double? get requiredRunRate {
    final balls = ballsRemaining;
    final needed = runsRequired;
    if (balls == null || needed == null || balls <= 0) return null;
    return needed * ballsPerOver / balls;
  }

  /// The over being bowled, or null between overs.
  OverSummary? get currentOver =>
      overs.isNotEmpty && !overs.last.isComplete ? overs.last : null;

  BatterCard? batter(String playerId) {
    for (final b in batters) {
      if (b.playerId == playerId) return b;
    }
    return null;
  }

  BowlerCard? bowler(String playerId) {
    for (final b in bowlers) {
      if (b.playerId == playerId) return b;
    }
    return null;
  }

  /// Fours and sixes off the bat, for boundary count-back.
  int get boundaries => batters.fold(0, (sum, b) => sum + b.fours + b.sixes);
}
