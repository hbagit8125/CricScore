/// Something only the scorer can tell the engine before play continues.
///
/// The UI asks exactly these questions, with [suggested] pre-selected.
sealed class PendingQuestion {
  const PendingQuestion();
}

final class ChooseOpeners extends PendingQuestion {
  const ChooseOpeners({
    required this.battingTeamId,
    required this.candidates,
    required this.suggestedStriker,
    required this.suggestedNonStriker,
  });

  final String battingTeamId;
  final List<String> candidates;
  final String suggestedStriker;
  final String suggestedNonStriker;
}

final class ChooseBatter extends PendingQuestion {
  const ChooseBatter({
    required this.battingTeamId,
    required this.candidates,
    required this.suggested,
    required this.atStrikersEnd,
  });

  final String battingTeamId;

  /// Players yet to bat, then retired batters who may return.
  final List<String> candidates;
  final String suggested;

  /// The new batter will face the next ball.
  final bool atStrikersEnd;
}

/// The side batting first leads by at least the follow-on margin and may
/// make the other side bat again straight away (Law 14).
final class ChooseFollowOn extends PendingQuestion {
  const ChooseFollowOn({
    required this.leadingTeamId,
    required this.trailingTeamId,
    required this.lead,
  });

  final String leadingTeamId;
  final String trailingTeamId;
  final int lead;
}

enum BowlerIneligibility {
  /// Would bowl more consecutive overs than allowed (Law 17.6).
  bowledPreviousOver,

  /// Has used their allowance of overs.
  quotaReached,

  /// Already bowling this over.
  currentBowler,

  /// Bowled in the previous super over.
  bowledPreviousSuperOver,
}

final class ChooseBowler extends PendingQuestion {
  const ChooseBowler({
    required this.bowlingTeamId,
    required this.eligible,
    required this.ineligible,
    required this.suggested,
    required this.midOver,
  });

  final String bowlingTeamId;

  /// In team order.
  final List<String> eligible;
  final Map<String, BowlerIneligibility> ineligible;

  /// Null only if nobody is eligible.
  final String? suggested;

  /// Replacing a bowler who could not finish the over.
  final bool midOver;
}
