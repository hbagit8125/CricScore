import 'dart:math' as math;

/// How many balls one bowler may bowl in an innings.
sealed class BowlerLimit {
  const BowlerLimit();

  /// Maximum legal balls for one bowler, or null for no limit.
  int? maxBalls({required int? inningsBalls, required int ballsPerOver});
}

/// No limit, as in Test and most first-class cricket.
final class NoBowlerLimit extends BowlerLimit {
  const NoBowlerLimit();

  @override
  int? maxBalls({required int? inningsBalls, required int ballsPerOver}) =>
      null;

  @override
  bool operator ==(Object other) => other is NoBowlerLimit;

  @override
  int get hashCode => (NoBowlerLimit).hashCode;
}

/// One fifth of the innings, rounded up to whole overs.
///
/// This is the usual limited-overs playing condition (4 overs in a T20,
/// 10 in an ODI) and it follows the innings when the overs are reduced.
final class FifthOfInnings extends BowlerLimit {
  const FifthOfInnings();

  @override
  int? maxBalls({required int? inningsBalls, required int ballsPerOver}) {
    if (inningsBalls == null) return null;
    final overs = (inningsBalls / ballsPerOver).ceil();
    return math.max(1, (overs / 5).ceil()) * ballsPerOver;
  }

  @override
  bool operator ==(Object other) => other is FifthOfInnings;

  @override
  int get hashCode => (FifthOfInnings).hashCode;
}

/// A fixed number of legal balls per bowler.
final class FixedBowlerLimit extends BowlerLimit {
  const FixedBowlerLimit(this.balls) : assert(balls > 0);

  final int balls;

  @override
  int? maxBalls({required int? inningsBalls, required int ballsPerOver}) =>
      balls;

  @override
  bool operator ==(Object other) =>
      other is FixedBowlerLimit && other.balls == balls;

  @override
  int get hashCode => balls.hashCode;
}

/// What happens when a limited-overs match ends with the scores level.
enum TieBreak {
  /// The result is a tie.
  none,

  /// Super overs are played until there is a winner (current ICC rule).
  superOverRepeat,

  /// One super over; if that is also tied, the side with more boundaries
  /// across the match and super over wins (pre-2019 ICC rule).
  superOverThenBoundaryCount,
}

/// The playing conditions for one match.
///
/// Presets cover the common formats; [copyWith] adjusts any value for local
/// or custom cricket.
final class MatchRules {
  const MatchRules({
    required this.name,
    this.playersPerSide = 11,
    this.ballsPerOver = 6,
    this.ballsPerInnings,
    this.bowlerLimit = const NoBowlerLimit(),
    this.maxConsecutiveOversPerBowler = 1,
    this.oversPerEnd = 1,
    this.wideRuns = 1,
    this.noBallRuns = 1,
    this.freeHitAfterNoBall = false,
    this.lbwAllowed = true,
    this.lastBatterCanBatAlone = false,
    this.retireAtRuns,
    this.tieBreak = TieBreak.none,
  });

  /// A starting point for local cricket: any overs and team size.
  factory MatchRules.custom({
    required int overs,
    int playersPerSide = 11,
    int ballsPerOver = 6,
  }) {
    return MatchRules(
      name: 'Custom',
      playersPerSide: playersPerSide,
      ballsPerOver: ballsPerOver,
      ballsPerInnings: overs * ballsPerOver,
      bowlerLimit: const FifthOfInnings(),
    );
  }

  /// 20 overs a side.
  static const t20 = MatchRules(
    name: 'T20',
    ballsPerInnings: 120,
    bowlerLimit: FifthOfInnings(),
    freeHitAfterNoBall: true,
    tieBreak: TieBreak.superOverRepeat,
  );

  /// 50 overs a side.
  static const odi = MatchRules(
    name: 'ODI',
    ballsPerInnings: 300,
    bowlerLimit: FifthOfInnings(),
    freeHitAfterNoBall: true,
    tieBreak: TieBreak.superOverRepeat,
  );

  /// 10 overs a side.
  static const t10 = MatchRules(
    name: 'T10',
    ballsPerInnings: 60,
    bowlerLimit: FifthOfInnings(),
    freeHitAfterNoBall: true,
    tieBreak: TieBreak.superOverRepeat,
  );

  /// 100 balls a side in sets of five; ends change every ten balls and a
  /// bowler may bowl five or ten in a row.
  ///
  /// Check the competition's current playing conditions before relying on
  /// the exact values.
  static const hundred = MatchRules(
    name: 'The Hundred',
    ballsPerOver: 5,
    ballsPerInnings: 100,
    bowlerLimit: FifthOfInnings(),
    maxConsecutiveOversPerBowler: 2,
    oversPerEnd: 2,
    freeHitAfterNoBall: true,
    tieBreak: TieBreak.superOverRepeat,
  );

  /// Limited-overs presets offered when creating a match.
  static const presets = [t20, odi, t10, hundred];

  /// Shown to the scorer, e.g. "T20".
  final String name;
  final int playersPerSide;
  final int ballsPerOver;

  /// Legal balls per innings, or null for no limit.
  final int? ballsPerInnings;
  final BowlerLimit bowlerLimit;

  /// Overs in a row one bowler may bowl. The Laws allow 1 (Law 17.6).
  final int maxConsecutiveOversPerBowler;

  /// Overs bowled from one end before the ends change.
  final int oversPerEnd;

  /// Penalty for a wide, before any runs taken.
  final int wideRuns;

  /// Penalty for a no-ball, before any runs taken.
  final int noBallRuns;
  final bool freeHitAfterNoBall;
  final bool lbwAllowed;

  /// When true the innings goes on with one batter after the last wicket
  /// partnership ends ("last man stands").
  final bool lastBatterCanBatAlone;

  /// A batter retires not out on reaching this score, if another batter
  /// can come in. Common in junior cricket.
  final int? retireAtRuns;
  final TieBreak tieBreak;

  /// The most wickets that can fall before the innings is all out.
  int get maxWickets =>
      lastBatterCanBatAlone ? playersPerSide : playersPerSide - 1;

  /// Problems that make these rules unusable, empty when valid.
  List<String> validate() {
    return [
      if (playersPerSide < 2) 'A side needs at least 2 players.',
      if (ballsPerOver < 1) 'An over needs at least 1 ball.',
      if (ballsPerInnings != null && ballsPerInnings! < 1)
        'An innings needs at least 1 ball.',
      if (maxConsecutiveOversPerBowler < 1)
        'A bowler must be allowed at least 1 over in a row.',
      if (oversPerEnd < 1) 'Ends must change after at least 1 over.',
      if (wideRuns < 0 || noBallRuns < 0) 'Penalty runs cannot be negative.',
      if (retireAtRuns != null && retireAtRuns! < 1)
        'Retirement score must be at least 1.',
    ];
  }

  MatchRules copyWith({
    String? name,
    int? playersPerSide,
    int? ballsPerOver,
    int? ballsPerInnings,
    bool clearBallsPerInnings = false,
    BowlerLimit? bowlerLimit,
    int? maxConsecutiveOversPerBowler,
    int? oversPerEnd,
    int? wideRuns,
    int? noBallRuns,
    bool? freeHitAfterNoBall,
    bool? lbwAllowed,
    bool? lastBatterCanBatAlone,
    int? retireAtRuns,
    bool clearRetireAtRuns = false,
    TieBreak? tieBreak,
  }) {
    return MatchRules(
      name: name ?? this.name,
      playersPerSide: playersPerSide ?? this.playersPerSide,
      ballsPerOver: ballsPerOver ?? this.ballsPerOver,
      ballsPerInnings: clearBallsPerInnings
          ? null
          : ballsPerInnings ?? this.ballsPerInnings,
      bowlerLimit: bowlerLimit ?? this.bowlerLimit,
      maxConsecutiveOversPerBowler:
          maxConsecutiveOversPerBowler ?? this.maxConsecutiveOversPerBowler,
      oversPerEnd: oversPerEnd ?? this.oversPerEnd,
      wideRuns: wideRuns ?? this.wideRuns,
      noBallRuns: noBallRuns ?? this.noBallRuns,
      freeHitAfterNoBall: freeHitAfterNoBall ?? this.freeHitAfterNoBall,
      lbwAllowed: lbwAllowed ?? this.lbwAllowed,
      lastBatterCanBatAlone:
          lastBatterCanBatAlone ?? this.lastBatterCanBatAlone,
      retireAtRuns: clearRetireAtRuns
          ? null
          : retireAtRuns ?? this.retireAtRuns,
      tieBreak: tieBreak ?? this.tieBreak,
    );
  }
}
