import '../model/events.dart';

/// "16.2" style overs for a count of legal balls.
String formatOvers(int legalBalls, int ballsPerOver) =>
    '${legalBalls ~/ ballsPerOver}.${legalBalls % ballsPerOver}';

enum BatterStatus {
  /// At the crease now.
  batting,

  /// Was batting when the innings closed.
  notOut,
  out,

  /// Retired hurt or otherwise not out; may come back.
  retiredNotOut,
}

final class DismissalRecord {
  const DismissalRecord({required this.kind, this.bowlerId, this.fielderId});

  final DismissalKind kind;

  /// Set only when the wicket is credited to the bowler.
  final String? bowlerId;
  final String? fielderId;
}

final class BatterCard {
  const BatterCard({
    required this.playerId,
    required this.position,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.status,
    this.dismissal,
  });

  final String playerId;

  /// Order of coming in, starting at 1.
  final int position;
  final int runs;

  /// Balls faced: legal balls and no-balls, not wides.
  final int balls;
  final int fours;
  final int sixes;
  final BatterStatus status;
  final DismissalRecord? dismissal;

  double get strikeRate => balls == 0 ? 0 : runs * 100 / balls;
}

final class BowlerCard {
  const BowlerCard({
    required this.playerId,
    required this.legalBalls,
    required this.maidens,
    required this.runs,
    required this.wickets,
    required this.wides,
    required this.noBalls,
    required this.dots,
  });

  final String playerId;
  final int legalBalls;
  final int maidens;

  /// Runs charged to the bowler: runs off the bat, wides and no-balls.
  final int runs;
  final int wickets;

  /// Number of wide deliveries.
  final int wides;

  /// Number of no-ball deliveries.
  final int noBalls;

  /// Legal balls with no runs charged to the bowler.
  final int dots;

  double economy(int ballsPerOver) =>
      legalBalls == 0 ? 0 : runs * ballsPerOver / legalBalls;

  /// "3.2-0-24-1"
  String figures(int ballsPerOver) =>
      '${formatOvers(legalBalls, ballsPerOver)}-$maidens-$runs-$wickets';
}

final class Extras {
  const Extras({
    this.wides = 0,
    this.noBalls = 0,
    this.byes = 0,
    this.legByes = 0,
    this.penalty = 0,
  });

  final int wides;
  final int noBalls;
  final int byes;
  final int legByes;
  final int penalty;

  int get total => wides + noBalls + byes + legByes + penalty;
}

final class FallOfWicket {
  const FallOfWicket({
    required this.wicket,
    required this.runs,
    required this.batterId,
    required this.legalBalls,
  });

  /// 1 for the first wicket.
  final int wicket;

  /// Team score when the wicket fell.
  final int runs;
  final String batterId;
  final int legalBalls;
}

final class Partnership {
  const Partnership({
    required this.batterIds,
    required this.runs,
    required this.balls,
  });

  /// One id when a batter is batting alone.
  final List<String> batterIds;

  /// All runs added, extras included.
  final int runs;

  /// Balls faced (legal balls and no-balls).
  final int balls;
}

/// One delivery as it happened, for the over-by-over timeline.
final class DeliveryRecord {
  const DeliveryRecord({
    required this.delivery,
    required this.bowlerId,
    required this.strikerId,
    required this.teamRuns,
    required this.totalRuns,
    required this.wasFreeHit,
  });

  final Delivery delivery;
  final String bowlerId;
  final String strikerId;

  /// Runs added to the team total, penalties included.
  final int totalRuns;

  /// Team score after this delivery.
  final int teamRuns;
  final bool wasFreeHit;
}

final class OverSummary {
  const OverSummary({
    required this.number,
    required this.bowlerIds,
    required this.deliveries,
    required this.isComplete,
  });

  /// 1 for the first over.
  final int number;

  /// More than one when a bowler was replaced during the over.
  final List<String> bowlerIds;
  final List<DeliveryRecord> deliveries;
  final bool isComplete;

  int get runs => deliveries.fold(0, (sum, d) => sum + d.totalRuns);
}
