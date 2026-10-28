import 'dart:math' as math;

/// How many balls one bowler may bowl in an innings.
sealed class BowlerLimit {
  const BowlerLimit();

  /// Legal balls each bowler may bowl, and how many bowlers may bowl one
  /// over more than that. Null for no limit.
  ({int balls, int extraOverBowlers})? allowance({
    required int? inningsBalls,
    required int ballsPerOver,
  });

  /// The most legal balls any one bowler may bowl, or null for no limit.
  int? maxBalls({required int? inningsBalls, required int ballsPerOver}) {
    final a = allowance(inningsBalls: inningsBalls, ballsPerOver: ballsPerOver);
    if (a == null) return null;
    return a.balls + (a.extraOverBowlers > 0 ? ballsPerOver : 0);
  }
}

/// No limit, as in Test and most first-class cricket.
final class NoBowlerLimit extends BowlerLimit {
  const NoBowlerLimit();

  @override
  ({int balls, int extraOverBowlers})? allowance({
    required int? inningsBalls,
    required int ballsPerOver,
  }) => null;

  @override
  bool operator ==(Object other) => other is NoBowlerLimit;

  @override
  int get hashCode => (NoBowlerLimit).hashCode;
}

/// One fifth of the innings (10 overs in an ODI). When the overs do not
/// divide by five, just enough bowlers may bowl one over more: in a
/// 41-over innings each bowler gets 8 and one bowler may bowl 9.
final class FifthOfInnings extends BowlerLimit {
  const FifthOfInnings();

  @override
  ({int balls, int extraOverBowlers})? allowance({
    required int? inningsBalls,
    required int ballsPerOver,
  }) {
    if (inningsBalls == null) return null;
    final overs = (inningsBalls / ballsPerOver).ceil();
    return (balls: (overs ~/ 5) * ballsPerOver, extraOverBowlers: overs % 5);
  }

  @override
  bool operator ==(Object other) => other is FifthOfInnings;

  @override
  int get hashCode => (FifthOfInnings).hashCode;
}

/// Twenty20 limits (also used by The Hundred, counting sets of five
/// balls as overs): 4 overs in a full innings. A shortened innings allows
/// 2 overs per bowler from 5 to 9 overs, 3 from 10 to 14 and 4 from 15 to
/// 19, as applied in published T20 international scorecards.
final class T20BowlerLimit extends BowlerLimit {
  const T20BowlerLimit();

  @override
  ({int balls, int extraOverBowlers})? allowance({
    required int? inningsBalls,
    required int ballsPerOver,
  }) {
    if (inningsBalls == null) return null;
    final overs = (inningsBalls / ballsPerOver).ceil();
    final each = overs >= 20 ? overs ~/ 5 : math.min(overs ~/ 5 + 1, 4);
    return (balls: each * ballsPerOver, extraOverBowlers: 0);
  }

  @override
  bool operator ==(Object other) => other is T20BowlerLimit;

  @override
  int get hashCode => (T20BowlerLimit).hashCode;
}

/// A fixed number of legal balls per bowler.
final class FixedBowlerLimit extends BowlerLimit {
  const FixedBowlerLimit(this.balls) : assert(balls > 0);

  final int balls;

  @override
  ({int balls, int extraOverBowlers})? allowance({
    required int? inningsBalls,
    required int ballsPerOver,
  }) => (balls: balls, extraOverBowlers: 0);

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
    this.inningsPerSide = 1,
    this.followOnMargin,
    this.days,
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

  /// A two-innings match of any length, such as a two-day club game, with
  /// the follow-on margin Law 14.1.1 gives for that many days.
  factory MatchRules.multiDay({required int days, int playersPerSide = 11}) {
    return MatchRules(
      name: '$days-day',
      playersPerSide: playersPerSide,
      inningsPerSide: 2,
      followOnMargin: followOnMarginForDays(days),
      days: days,
    );
  }

  /// 20 overs a side.
  static const t20 = MatchRules(
    name: 'T20',
    ballsPerInnings: 120,
    bowlerLimit: T20BowlerLimit(),
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
  /// Published ball-by-ball data shows a no-ball worth 2 runs from 2021 to
  /// 2025 and 1 run from 2026; adjust [noBallRuns] for older seasons.
  static const hundred = MatchRules(
    name: 'The Hundred',
    ballsPerOver: 5,
    ballsPerInnings: 100,
    bowlerLimit: T20BowlerLimit(),
    maxConsecutiveOversPerBowler: 2,
    oversPerEnd: 2,
    freeHitAfterNoBall: true,
    tieBreak: TieBreak.superOverRepeat,
  );

  /// Five-day Test: two innings each, follow-on at 200.
  static const test = MatchRules(
    name: 'Test',
    inningsPerSide: 2,
    followOnMargin: 200,
    days: 5,
  );

  /// Four-day first-class match: two innings each, follow-on at 150.
  static const firstClass = MatchRules(
    name: 'First-class',
    inningsPerSide: 2,
    followOnMargin: 150,
    days: 4,
  );

  /// Limited-overs presets offered when creating a match.
  static const presets = [t20, odi, t10, hundred];

  /// Two-innings presets.
  static const multiDayPresets = [test, firstClass];

  /// Law 14.1.1 follow-on margin for a two-innings match of [days] days.
  static int followOnMarginForDays(int days) => switch (days) {
    >= 5 => 200,
    >= 3 => 150,
    2 => 100,
    _ => 75,
  };

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

  /// 1 for limited-overs cricket, 2 for Tests and first-class matches.
  final int inningsPerSide;

  /// Lead after the first innings at which the side batting first may
  /// make the other side follow on (Law 14), or null for no follow-on.
  final int? followOnMargin;

  /// Scheduled days of play, or null for a one-day match.
  final int? days;

  bool get isTwoInnings => inningsPerSide == 2;

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
      if (inningsPerSide != 1 && inningsPerSide != 2)
        'Each side has 1 or 2 innings.',
      if (inningsPerSide == 2 && tieBreak != TieBreak.none)
        'Super overs are only for one-innings matches.',
      if (followOnMargin != null &&
          (inningsPerSide != 2 || followOnMargin! < 1))
        'The follow-on needs a two-innings match and a positive margin.',
      if (days != null && days! < 1) 'A match needs at least 1 day.',
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
    int? inningsPerSide,
    int? followOnMargin,
    bool clearFollowOnMargin = false,
    int? days,
    bool clearDays = false,
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
      inningsPerSide: inningsPerSide ?? this.inningsPerSide,
      followOnMargin: clearFollowOnMargin
          ? null
          : followOnMargin ?? this.followOnMargin,
      days: clearDays ? null : days ?? this.days,
    );
  }
}
