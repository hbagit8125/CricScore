import '../engine_info.dart';
import '../model/events.dart';
import '../model/match_setup.dart';
import '../model/team.dart';
import '../rules/match_rules.dart';

/// JSON form of match setups and events, for storage and sync.
///
/// Every stored document carries [engineSchemaVersion] so older data can be
/// migrated when the format changes. Readers reject data from a newer
/// version instead of guessing.
abstract final class MatchJson {
  static Map<String, Object?> setupToJson(MatchSetup s) => {
    'v': engineSchemaVersion,
    'rules': rulesToJson(s.rules),
    'teamA': _teamToJson(s.teamA),
    'teamB': _teamToJson(s.teamB),
    'toss': {'wonBy': s.toss.wonByTeamId, 'decision': s.toss.decision.name},
  };

  static MatchSetup setupFromJson(Map<String, Object?> json) {
    _checkVersion(json);
    final toss = _map(json['toss']);
    return MatchSetup(
      rules: rulesFromJson(_map(json['rules'])),
      teamA: _teamFromJson(_map(json['teamA'])),
      teamB: _teamFromJson(_map(json['teamB'])),
      toss: Toss(
        wonByTeamId: toss['wonBy']! as String,
        decision: TossDecision.values.byName(toss['decision']! as String),
      ),
    );
  }

  static Map<String, Object?> rulesToJson(MatchRules r) => {
    'name': r.name,
    'playersPerSide': r.playersPerSide,
    'ballsPerOver': r.ballsPerOver,
    'ballsPerInnings': r.ballsPerInnings,
    'bowlerLimit': switch (r.bowlerLimit) {
      NoBowlerLimit() => {'type': 'none'},
      FifthOfInnings() => {'type': 'fifth'},
      T20BowlerLimit() => {'type': 't20'},
      FixedBowlerLimit(:final balls) => {'type': 'fixed', 'balls': balls},
    },
    'maxConsecutiveOversPerBowler': r.maxConsecutiveOversPerBowler,
    'oversPerEnd': r.oversPerEnd,
    'wideRuns': r.wideRuns,
    'noBallRuns': r.noBallRuns,
    'freeHitAfterNoBall': r.freeHitAfterNoBall,
    'lbwAllowed': r.lbwAllowed,
    'lastBatterCanBatAlone': r.lastBatterCanBatAlone,
    'retireAtRuns': r.retireAtRuns,
    'tieBreak': r.tieBreak.name,
    'inningsPerSide': r.inningsPerSide,
    'followOnMargin': r.followOnMargin,
  };

  static MatchRules rulesFromJson(Map<String, Object?> j) {
    final limit = _map(j['bowlerLimit']);
    return MatchRules(
      name: j['name']! as String,
      playersPerSide: j['playersPerSide']! as int,
      ballsPerOver: j['ballsPerOver']! as int,
      ballsPerInnings: j['ballsPerInnings'] as int?,
      bowlerLimit: switch (limit['type']) {
        'none' => const NoBowlerLimit(),
        'fifth' => const FifthOfInnings(),
        't20' => const T20BowlerLimit(),
        'fixed' => FixedBowlerLimit(limit['balls']! as int),
        final t => throw FormatException('Unknown bowler limit "$t".'),
      },
      maxConsecutiveOversPerBowler: j['maxConsecutiveOversPerBowler']! as int,
      oversPerEnd: j['oversPerEnd']! as int,
      wideRuns: j['wideRuns']! as int,
      noBallRuns: j['noBallRuns']! as int,
      freeHitAfterNoBall: j['freeHitAfterNoBall']! as bool,
      lbwAllowed: j['lbwAllowed']! as bool,
      lastBatterCanBatAlone: j['lastBatterCanBatAlone']! as bool,
      retireAtRuns: j['retireAtRuns'] as int?,
      tieBreak: TieBreak.values.byName(j['tieBreak']! as String),
      inningsPerSide: j['inningsPerSide']! as int,
      followOnMargin: j['followOnMargin'] as int?,
    );
  }

  static Map<String, Object?> eventToJson(MatchEvent e) => switch (e) {
    OpenersSelected(:final strikerId, :final nonStrikerId) => {
      'type': 'openers',
      'striker': strikerId,
      'nonStriker': nonStrikerId,
    },
    BowlerSelected(:final bowlerId, :final umpireAllowed) => {
      'type': 'bowler',
      'player': bowlerId,
      if (umpireAllowed) 'umpireAllowed': true,
    },
    BatterIn(:final batterId) => {'type': 'batterIn', 'player': batterId},
    SwapStrike() => {'type': 'swapStrike'},
    Retired(:final batterId, :final out) => {
      'type': 'retired',
      'player': batterId,
      'out': out,
    },
    TimedOut(:final batterId) => {'type': 'timedOut', 'player': batterId},
    RunOutBeforeDelivery(:final batterId) => {
      'type': 'runOutBeforeDelivery',
      'player': batterId,
    },
    RevisedTarget(:final ballsPerInnings, :final target) => {
      'type': 'revisedTarget',
      'balls': ?ballsPerInnings,
      'target': ?target,
    },
    EndInnings() => {'type': 'endInnings'},
    Abandoned() => {'type': 'abandoned'},
    Declare() => {'type': 'declare'},
    Forfeit() => {'type': 'forfeit'},
    FollowOn(:final enforce) => {'type': 'followOn', 'enforce': enforce},
    FollowOnMarginSet(:final runs) => {'type': 'followOnMargin', 'runs': runs},
    Drawn() => {'type': 'drawn'},
    PenaltyRuns(:final teamId, :final runs) => {
      'type': 'penalty',
      'team': teamId,
      'runs': runs,
    },
    Substitute(:final outPlayerId, :final inPlayerId, :final reason) => {
      'type': 'substitute',
      'out': outPlayerId,
      'in': inPlayerId,
      'reason': reason.name,
    },
    OverCalledEarly() => {'type': 'overCalledEarly'},
    OverExtended() => {'type': 'overExtended'},
    Delivery() => _deliveryToJson(e),
  };

  static MatchEvent eventFromJson(Map<String, Object?> j) {
    String s(String key) => j[key]! as String;
    return switch (j['type']) {
      'openers' => OpenersSelected(
        strikerId: s('striker'),
        nonStrikerId: s('nonStriker'),
      ),
      'bowler' => BowlerSelected(
        s('player'),
        umpireAllowed: j['umpireAllowed'] as bool? ?? false,
      ),
      'batterIn' => BatterIn(s('player')),
      'swapStrike' => const SwapStrike(),
      'retired' => Retired(s('player'), out: j['out']! as bool),
      'timedOut' => TimedOut(s('player')),
      'runOutBeforeDelivery' => RunOutBeforeDelivery(s('player')),
      'revisedTarget' => RevisedTarget(
        ballsPerInnings: j['balls'] as int?,
        target: j['target'] as int?,
      ),
      'endInnings' => const EndInnings(),
      'abandoned' => const Abandoned(),
      'declare' => const Declare(),
      'forfeit' => const Forfeit(),
      'followOn' => FollowOn(enforce: j['enforce']! as bool),
      'followOnMargin' => FollowOnMarginSet(j['runs']! as int),
      'drawn' => const Drawn(),
      'penalty' => PenaltyRuns(teamId: s('team'), runs: j['runs']! as int),
      'substitute' => Substitute(
        outPlayerId: s('out'),
        inPlayerId: s('in'),
        reason: SubstitutionReason.values.byName(s('reason')),
      ),
      'overCalledEarly' => const OverCalledEarly(),
      'overExtended' => const OverExtended(),
      'delivery' => _deliveryFromJson(j),
      final t => throw FormatException('Unknown event type "$t".'),
    };
  }

  /// Deliveries are by far the most common event, so default values are
  /// left out.
  static Map<String, Object?> _deliveryToJson(Delivery d) {
    final dismissal = d.dismissal;
    return {
      'type': 'delivery',
      if (d.kind != DeliveryKind.legal) 'kind': d.kind.name,
      if (d.runsTo != RunsTo.batter) 'runsTo': d.runsTo.name,
      if (d.completedRuns != 0) 'runs': d.completedRuns,
      if (d.boundary != 0) 'boundary': d.boundary,
      if (dismissal != null)
        'out': {
          'kind': dismissal.kind.name,
          'player': dismissal.batterId,
          'fielder': ?dismissal.fielderId,
          if (dismissal.crossed) 'crossed': true,
        },
    };
  }

  static Delivery _deliveryFromJson(Map<String, Object?> j) {
    final out = j['out'] as Map<String, Object?>?;
    return Delivery(
      kind: DeliveryKind.values.byName(j['kind'] as String? ?? 'legal'),
      runsTo: RunsTo.values.byName(j['runsTo'] as String? ?? 'batter'),
      completedRuns: j['runs'] as int? ?? 0,
      boundary: j['boundary'] as int? ?? 0,
      dismissal: out == null
          ? null
          : Dismissal(
              kind: DismissalKind.values.byName(out['kind']! as String),
              batterId: out['player']! as String,
              fielderId: out['fielder'] as String?,
              crossed: out['crossed'] as bool? ?? false,
            ),
    );
  }

  static Map<String, Object?> _teamToJson(TeamSheet t) => {
    'id': t.id,
    'name': t.name,
    'players': [for (final p in t.players) _playerToJson(p)],
    if (t.substitutes.isNotEmpty)
      'substitutes': [for (final p in t.substitutes) _playerToJson(p)],
  };

  static TeamSheet _teamFromJson(Map<String, Object?> j) => TeamSheet(
    id: j['id']! as String,
    name: j['name']! as String,
    players: [for (final p in j['players']! as List) _playerFromJson(_map(p))],
    substitutes: [
      for (final p in (j['substitutes'] as List?) ?? const [])
        _playerFromJson(_map(p)),
    ],
  );

  static Map<String, Object?> _playerToJson(PlayerRef p) => {
    'id': p.id,
    'name': p.name,
  };

  static PlayerRef _playerFromJson(Map<String, Object?> j) =>
      PlayerRef(id: j['id']! as String, name: j['name']! as String);

  static Map<String, Object?> _map(Object? o) =>
      (o! as Map).cast<String, Object?>();

  static void _checkVersion(Map<String, Object?> json) {
    final v = json['v'] as int? ?? 1;
    if (v > engineSchemaVersion) {
      throw FormatException(
        'This match was saved by a newer version of CricScore '
        '(format $v). Update the app to open it.',
      );
    }
  }
}
