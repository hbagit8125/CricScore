/// Everything the scorer records is a [MatchEvent]. The match state is
/// rebuilt by replaying the events in order, so undo and edit are exact.
sealed class MatchEvent {
  const MatchEvent();
}

/// The two batters who open the innings.
final class OpenersSelected extends MatchEvent {
  const OpenersSelected({required this.strikerId, required this.nonStrikerId});

  final String strikerId;
  final String nonStrikerId;

  @override
  bool operator ==(Object other) =>
      other is OpenersSelected &&
      other.strikerId == strikerId &&
      other.nonStrikerId == nonStrikerId;

  @override
  int get hashCode => Object.hash(strikerId, nonStrikerId);
}

/// The bowler for the next over, or a replacement who finishes the current
/// over (Law 17.8).
///
/// With [umpireAllowed] the umpire let the bowler bowl although the
/// records say they may not (consecutive overs or their allowance of
/// overs). The scorer records what happened on the field.
final class BowlerSelected extends MatchEvent {
  const BowlerSelected(this.bowlerId, {this.umpireAllowed = false});

  final String bowlerId;
  final bool umpireAllowed;

  @override
  bool operator ==(Object other) =>
      other is BowlerSelected &&
      other.bowlerId == bowlerId &&
      other.umpireAllowed == umpireAllowed;

  @override
  int get hashCode => Object.hash(bowlerId, umpireAllowed);
}

/// A new or returning batter takes the vacant end.
final class BatterIn extends MatchEvent {
  const BatterIn(this.batterId);

  final String batterId;

  @override
  bool operator ==(Object other) =>
      other is BatterIn && other.batterId == batterId;

  @override
  int get hashCode => batterId.hashCode;
}

/// Correct which batter is on strike.
final class SwapStrike extends MatchEvent {
  const SwapStrike();

  @override
  bool operator ==(Object other) => other is SwapStrike;

  @override
  int get hashCode => (SwapStrike).hashCode;
}

/// A batter at the crease retires between deliveries (Law 25.4).
///
/// Retired out counts as a wicket; retired not out (for example hurt) does
/// not, and the batter may come back later.
final class Retired extends MatchEvent {
  const Retired(this.batterId, {required this.out});

  final String batterId;
  final bool out;

  @override
  bool operator ==(Object other) =>
      other is Retired && other.batterId == batterId && other.out == out;

  @override
  int get hashCode => Object.hash(batterId, out);
}

/// The incoming batter was not ready in time (Law 40). Counts as a wicket.
final class TimedOut extends MatchEvent {
  const TimedOut(this.batterId);

  final String batterId;

  @override
  bool operator ==(Object other) =>
      other is TimedOut && other.batterId == batterId;

  @override
  int get hashCode => batterId.hashCode;
}

/// The bowler runs out the non-striker for leaving their ground before the
/// ball is bowled (Law 38.3). No ball is counted.
final class RunOutBeforeDelivery extends MatchEvent {
  const RunOutBeforeDelivery(this.batterId);

  final String batterId;

  @override
  bool operator ==(Object other) =>
      other is RunOutBeforeDelivery && other.batterId == batterId;

  @override
  int get hashCode => batterId.hashCode;
}

/// The umpire called "over" before the full number of legal balls. The
/// over stands as called (Law 17.5).
final class OverCalledEarly extends MatchEvent {
  const OverCalledEarly();

  @override
  bool operator ==(Object other) => other is OverCalledEarly;

  @override
  int get hashCode => (OverCalledEarly).hashCode;
}

/// The umpire allowed one more ball in the over just completed, which
/// stands (Law 17.5). Recorded straight after the over's last ball.
final class OverExtended extends MatchEvent {
  const OverExtended();

  @override
  bool operator ==(Object other) => other is OverExtended;

  @override
  int get hashCode => (OverExtended).hashCode;
}

/// Shortened innings or a revised target after an interruption, as
/// supplied by the officials (for example from a DLS calculation).
///
/// Applies to the innings in progress, or to the next one at an innings
/// break.
final class RevisedTarget extends MatchEvent {
  const RevisedTarget({this.ballsPerInnings, this.target})
    : assert(ballsPerInnings != null || target != null);

  final int? ballsPerInnings;

  /// Runs needed to win. Only valid for the second innings.
  final int? target;

  @override
  bool operator ==(Object other) =>
      other is RevisedTarget &&
      other.ballsPerInnings == ballsPerInnings &&
      other.target == target;

  @override
  int get hashCode => Object.hash(ballsPerInnings, target);
}

/// The scorer closes the innings, for example when no remaining batter is
/// able to bat.
final class EndInnings extends MatchEvent {
  const EndInnings();

  @override
  bool operator ==(Object other) => other is EndInnings;

  @override
  int get hashCode => (EndInnings).hashCode;
}

/// The batting side declares its innings closed (Law 15.1). Two-innings
/// matches only.
final class Declare extends MatchEvent {
  const Declare();

  @override
  bool operator ==(Object other) => other is Declare;

  @override
  int get hashCode => (Declare).hashCode;
}

/// The batting side forfeits the innings before it starts (Law 15.2).
/// Two-innings matches only.
final class Forfeit extends MatchEvent {
  const Forfeit();

  @override
  bool operator ==(Object other) => other is Forfeit;

  @override
  int get hashCode => (Forfeit).hashCode;
}

/// The side that batted first decides whether to enforce the follow-on
/// (Law 14).
final class FollowOn extends MatchEvent {
  const FollowOn({required this.enforce});

  final bool enforce;

  @override
  bool operator ==(Object other) =>
      other is FollowOn && other.enforce == enforce;

  @override
  int get hashCode => enforce.hashCode;
}

/// The follow-on margin set by the officials when playing time has been
/// lost, based on the days left (Law 14.1.3). Recorded before the second
/// innings ends.
final class FollowOnMarginSet extends MatchEvent {
  const FollowOnMarginSet(this.runs);

  final int runs;

  @override
  bool operator ==(Object other) =>
      other is FollowOnMarginSet && other.runs == runs;

  @override
  int get hashCode => runs.hashCode;
}

/// Time ran out in a two-innings match without a result (Law 16.3.2).
final class Drawn extends MatchEvent {
  const Drawn();

  @override
  bool operator ==(Object other) => other is Drawn;

  @override
  int get hashCode => (Drawn).hashCode;
}

/// Penalty runs awarded to a side (Law 41), usually 5.
///
/// Added to that side's innings in progress; otherwise to its most recent
/// completed innings, or to its next innings if it has not batted yet.
final class PenaltyRuns extends MatchEvent {
  const PenaltyRuns({required this.teamId, this.runs = 5});

  final String teamId;
  final int runs;

  @override
  bool operator ==(Object other) =>
      other is PenaltyRuns && other.teamId == teamId && other.runs == runs;

  @override
  int get hashCode => Object.hash(teamId, runs);
}

enum SubstitutionReason { concussion, impactPlayer, other }

/// A named substitute replaces a player for the rest of the match. The
/// replaced player can no longer bat or bowl.
final class Substitute extends MatchEvent {
  const Substitute({
    required this.outPlayerId,
    required this.inPlayerId,
    required this.reason,
  });

  final String outPlayerId;
  final String inPlayerId;
  final SubstitutionReason reason;

  @override
  bool operator ==(Object other) =>
      other is Substitute &&
      other.outPlayerId == outPlayerId &&
      other.inPlayerId == inPlayerId &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(outPlayerId, inPlayerId, reason);
}

enum StoppageKind {
  drinks,
  lunch,
  tea,

  /// Close of play for the day ("stumps"). The next day starts after it.
  stumps,

  /// Rain or bad light.
  weather,
  other,
}

/// Play stops for an interval, the close of a day or an interruption
/// (Laws 11 and 12). It resumes with the next ball; nothing else changes.
final class Stoppage extends MatchEvent {
  const Stoppage(this.kind);

  final StoppageKind kind;

  @override
  bool operator ==(Object other) => other is Stoppage && other.kind == kind;

  @override
  int get hashCode => kind.hashCode;
}

/// The match is abandoned without a result.
final class Abandoned extends MatchEvent {
  const Abandoned();

  @override
  bool operator ==(Object other) => other is Abandoned;

  @override
  int get hashCode => (Abandoned).hashCode;
}

enum DeliveryKind { legal, wide, noBall }

/// Who the runs from a delivery are credited to. All runs on a wide are
/// wides, so a wide always uses [batter] and the runs are recorded as wides.
enum RunsTo { batter, byes, legByes }

enum DismissalKind {
  bowled,
  caught,
  lbw,
  stumped,
  hitWicket,
  runOut,
  obstructingTheField,
  hitTheBallTwice,
  timedOut,
  retiredOut;

  /// Wickets the bowler gets credit for (Law 32-36, 39).
  bool get creditedToBowler => switch (this) {
    bowled || caught || lbw || stumped || hitWicket => true,
    _ => false,
  };

  /// Dismissals where only the striker can be out.
  bool get strikerOnly => switch (this) {
    bowled || caught || lbw || stumped || hitWicket || hitTheBallTwice => true,
    _ => false,
  };

  /// Dismissals after which no runs are scored from the delivery, apart
  /// from wide or no-ball penalties.
  bool get endsDeliveryWithoutRuns => switch (this) {
    bowled || caught || lbw || stumped || hitWicket || hitTheBallTwice => true,
    _ => false,
  };
}

final class Dismissal {
  const Dismissal({
    required this.kind,
    required this.batterId,
    this.fielderId,
    this.crossed = false,
  });

  final DismissalKind kind;
  final String batterId;

  /// Catcher, wicketkeeper or fielder involved, when known.
  final String? fielderId;

  /// Run out only: the batters had crossed on the run they were attempting
  /// (Law 38.2). Decides which end the not-out batter ends up at.
  final bool crossed;

  @override
  bool operator ==(Object other) =>
      other is Dismissal &&
      other.kind == kind &&
      other.batterId == batterId &&
      other.fielderId == fielderId &&
      other.crossed == crossed;

  @override
  int get hashCode => Object.hash(kind, batterId, fielderId, crossed);
}

/// One ball bowled.
///
/// Runs are split into [completedRuns] (run between the wickets, which
/// decides the strike) and [boundary] (4 or 6 allowance, which does not).
final class Delivery extends MatchEvent {
  const Delivery({
    this.kind = DeliveryKind.legal,
    this.runsTo = RunsTo.batter,
    this.completedRuns = 0,
    this.boundary = 0,
    this.dismissal,
  });

  const Delivery.dot() : this();

  const Delivery.runs(int runs) : this(completedRuns: runs);

  const Delivery.four() : this(boundary: 4);

  const Delivery.six() : this(boundary: 6);

  /// A wide with any runs taken; [boundary] true for a wide that reaches
  /// the boundary.
  const Delivery.wide({int runs = 0, bool boundary = false})
    : this(
        kind: DeliveryKind.wide,
        completedRuns: runs,
        boundary: boundary ? 4 : 0,
      );

  const Delivery.noBall({
    RunsTo runsTo = RunsTo.batter,
    int runs = 0,
    int boundary = 0,
    Dismissal? dismissal,
  }) : this(
         kind: DeliveryKind.noBall,
         runsTo: runsTo,
         completedRuns: runs,
         boundary: boundary,
         dismissal: dismissal,
       );

  const Delivery.byes(int runs, {bool boundary = false})
    : this(
        runsTo: RunsTo.byes,
        completedRuns: runs,
        boundary: boundary ? 4 : 0,
      );

  const Delivery.legByes(int runs, {bool boundary = false})
    : this(
        runsTo: RunsTo.legByes,
        completedRuns: runs,
        boundary: boundary ? 4 : 0,
      );

  const Delivery.wicket(Dismissal dismissal, {int runs = 0})
    : this(completedRuns: runs, dismissal: dismissal);

  final DeliveryKind kind;
  final RunsTo runsTo;
  final int completedRuns;

  /// 0, 4 or 6.
  final int boundary;
  final Dismissal? dismissal;

  bool get isLegal => kind == DeliveryKind.legal;

  /// Runs from running and boundaries, before wide or no-ball penalties.
  int get runs => completedRuns + boundary;

  @override
  bool operator ==(Object other) =>
      other is Delivery &&
      other.kind == kind &&
      other.runsTo == runsTo &&
      other.completedRuns == completedRuns &&
      other.boundary == boundary &&
      other.dismissal == dismissal;

  @override
  int get hashCode =>
      Object.hash(kind, runsTo, completedRuns, boundary, dismissal);
}
