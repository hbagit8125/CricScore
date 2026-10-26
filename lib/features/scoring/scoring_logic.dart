import 'package:cricket_engine/cricket_engine.dart';

/// An extra armed on the keypad, waiting for the runs key.
enum ArmedExtra {
  none,
  wide,
  noBall,
  byes,
  legByes,

  /// No-ball where the runs were byes.
  noBallByes,

  /// No-ball where the runs were leg byes.
  noBallLegByes;

  DeliveryKind get deliveryKind => switch (this) {
    wide => DeliveryKind.wide,
    noBall || noBallByes || noBallLegByes => DeliveryKind.noBall,
    _ => DeliveryKind.legal,
  };

  RunsTo get runsTo => switch (this) {
    byes || noBallByes => RunsTo.byes,
    legByes || noBallLegByes => RunsTo.legByes,
    _ => RunsTo.batter,
  };

  /// Six can only come off the bat.
  bool get allowsSix => this == none || this == noBall;

  /// Zero byes is not a thing; a dot ball is recorded instead.
  bool get allowsZero => runsTo == RunsTo.batter;

  /// Tapping an extra key again disarms it; byes and leg byes combine with
  /// an armed no-ball.
  ArmedExtra toggle(ArmedExtra key) => switch ((this, key)) {
    (noBall, byes) => noBallByes,
    (noBall, legByes) => noBallLegByes,
    (noBallByes, byes) || (noBallLegByes, legByes) => noBall,
    _ when this == key => none,
    _ => key,
  };
}

/// The delivery for a runs key pressed with [extra] armed. A 4 counts as a
/// boundary; 0-3 and 5 as runs taken.
Delivery deliveryFor(ArmedExtra extra, int runs, {Dismissal? dismissal}) {
  final boundary = (runs == 4 || runs == 6) && dismissal == null ? runs : 0;
  return Delivery(
    kind: extra.deliveryKind,
    runsTo: extra.runsTo,
    completedRuns: boundary == 0 ? runs : 0,
    boundary: boundary,
    dismissal: dismissal,
  );
}

/// Short label for a ball in the over strip, e.g. `•`, `4`, `2wd`, `nb4`,
/// `1lb`, `W`.
String ballLabel(Delivery d, MatchRules rules) {
  final runs = d.runs;
  final String base;
  switch (d.kind) {
    case DeliveryKind.wide:
      final w = rules.wideRuns + runs;
      base = w == 1 ? 'wd' : '${w}wd';
    case DeliveryKind.noBall:
      final suffix = switch (d.runsTo) {
        RunsTo.batter => runs == 0 ? '' : '$runs',
        RunsTo.byes => '+${runs}b',
        RunsTo.legByes => '+${runs}lb',
      };
      base = 'nb$suffix';
    case DeliveryKind.legal:
      base = switch (d.runsTo) {
        RunsTo.batter => runs == 0 ? '•' : '$runs',
        RunsTo.byes => '${runs}b',
        RunsTo.legByes => '${runs}lb',
      };
  }
  if (d.dismissal == null) return base;
  if (base == '•') return 'W';
  return '$base W';
}

/// Plain names for dismissal kinds, as the scorer chooses them.
String dismissalName(DismissalKind k) => switch (k) {
  DismissalKind.bowled => 'Bowled',
  DismissalKind.caught => 'Caught',
  DismissalKind.lbw => 'LBW',
  DismissalKind.stumped => 'Stumped',
  DismissalKind.hitWicket => 'Hit wicket',
  DismissalKind.runOut => 'Run out',
  DismissalKind.obstructingTheField => 'Obstructing the field',
  DismissalKind.hitTheBallTwice => 'Hit the ball twice',
  DismissalKind.timedOut => 'Timed out',
  DismissalKind.retiredOut => 'Retired out',
};

/// "Caught Shah b Ali", "b Ali", "run out (Khan)", "not out"…
String howOut(BatterCard b, String Function(String) name) {
  final d = b.dismissal;
  if (d == null) {
    return switch (b.status) {
      BatterStatus.batting || BatterStatus.notOut => 'not out',
      BatterStatus.retiredNotOut => 'retired not out',
      BatterStatus.out => 'out',
    };
  }
  final bowler = d.bowlerId == null ? null : name(d.bowlerId!);
  final fielder = d.fielderId == null ? null : name(d.fielderId!);
  return switch (d.kind) {
    DismissalKind.bowled => 'b $bowler',
    DismissalKind.lbw => 'lbw b $bowler',
    DismissalKind.caught when fielder == null => 'c ? b $bowler',
    DismissalKind.caught when fielder == bowler => 'c & b $bowler',
    DismissalKind.caught => 'c $fielder b $bowler',
    DismissalKind.stumped => 'st ${fielder ?? '?'} b $bowler',
    DismissalKind.hitWicket => 'hit wicket b $bowler',
    DismissalKind.runOut => fielder == null ? 'run out' : 'run out ($fielder)',
    final k => dismissalName(k).toLowerCase(),
  };
}

/// Overs as scorers show them; The Hundred counts balls.
String oversLabel(InningsState inn) =>
    inn.ballsPerOver == 5 ? '${inn.legalBalls} balls' : '${inn.oversText} ov';

/// "Need 39 off 22 balls" while chasing; null otherwise.
String? chaseLine(InningsState inn) {
  final need = inn.runsRequired;
  if (need == null || inn.isClosed) return null;
  final left = inn.ballsRemaining;
  if (left == null) return 'Need $need to win';
  return 'Need $need off $left ${left == 1 ? 'ball' : 'balls'}';
}
