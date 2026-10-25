// Replays Cricsheet ball-by-ball JSON (https://cricsheet.org, Open Data
// Commons Attribution License) through the engine and compares the result
// with the published scorecard.

import 'package:cricket_engine/cricket_engine.dart';
import 'package:cricket_engine/src/engine/scorer.dart';

final class CricsheetReplay {
  CricsheetReplay(this.name);

  final String name;
  MatchSetup? setup;
  final List<MatchEvent> events = [];

  /// Why the match was not replayed, for data the engine cannot score
  /// (bowl-outs, awarded matches, uneven sides).
  String? skipped;

  /// The engine refused an event or disagreed with the published scorecard.
  final List<String> mismatches = [];

  /// Places where the data needed a correction the scorer would make by
  /// hand, such as an unrecorded change of strike. Counted, not failures.
  final Map<String, int> corrections = {};

  MatchState? state;

  bool get ok => skipped == null && mismatches.isEmpty;

  void _correct(String kind) =>
      corrections.update(kind, (n) => n + 1, ifAbsent: () => 1);
}

const _deliveryDismissals = {
  'bowled': DismissalKind.bowled,
  'caught': DismissalKind.caught,
  'caught and bowled': DismissalKind.caught,
  'lbw': DismissalKind.lbw,
  'stumped': DismissalKind.stumped,
  'hit wicket': DismissalKind.hitWicket,
  'run out': DismissalKind.runOut,
  'obstructing the field': DismissalKind.obstructingTheField,
  'handled the ball': DismissalKind.obstructingTheField,
  'hit the ball twice': DismissalKind.hitTheBallTwice,
};

CricsheetReplay replayCricsheet(String name, Map<String, dynamic> json) {
  final replay = CricsheetReplay(name);
  try {
    _replay(replay, json);
  } on _Abort catch (e) {
    replay.mismatches.add(e.message);
  } on IllegalEventException catch (e) {
    replay.mismatches.add('refused: ${e.message}');
  }
  return replay;
}

final class _Abort implements Exception {
  _Abort(this.message);
  final String message;
}

void _replay(CricsheetReplay replay, Map<String, dynamic> json) {
  final info = json['info'] as Map<String, dynamic>;
  final inningsData = (json['innings'] as List).cast<Map<String, dynamic>>();
  final outcome = info['outcome'] as Map<String, dynamic>;
  if (info.containsKey('bowl_out') || outcome.containsKey('bowl_out')) {
    replay.skipped = 'bowl-out';
    return;
  }
  if (outcome['method'] == 'Awarded') {
    replay.skipped = 'match awarded';
    return;
  }

  final teams = (info['teams'] as List).cast<String>();
  final people = ((info['registry'] as Map)['people'] as Map)
      .cast<String, String>();
  String id(String name) => people[name] ?? name;

  // Players brought in by match-long replacements are substitutes.
  final subsIn = <String, Set<String>>{for (final t in teams) t: {}};
  for (final inn in inningsData) {
    for (final over in (inn['overs'] as List).cast<Map<String, dynamic>>()) {
      for (final d
          in (over['deliveries'] as List).cast<Map<String, dynamic>>()) {
        final repl = d['replacements'] as Map<String, dynamic>?;
        for (final r
            in ((repl?['match'] as List?) ?? const [])
                .cast<Map<String, dynamic>>()) {
          subsIn[r['team'] as String]!.add(r['in'] as String);
        }
      }
    }
  }
  final playersByTeam = (info['players'] as Map).cast<String, List<dynamic>>();
  TeamSheet sheet(String team) {
    final all = playersByTeam[team]!.cast<String>();
    return TeamSheet(
      id: team,
      name: team,
      players: [
        for (final p in all)
          if (!subsIn[team]!.contains(p)) PlayerRef(id: id(p), name: p),
      ],
      substitutes: [
        for (final p in subsIn[team]!) PlayerRef(id: id(p), name: p),
      ],
    );
  }

  final a = sheet(teams[0]);
  final b = sheet(teams[1]);
  if (a.players.length != b.players.length) {
    replay.skipped = 'sides of ${a.players.length} and ${b.players.length}';
    return;
  }

  final matchType = info['match_type'] as String;
  final bpo = info['balls_per_over'] as int? ?? 6;
  final date = (info['dates'] as List).first as String;
  final hasSuperOver = inningsData.any((i) => i['super_over'] == true);
  final tieBreak = !hasSuperOver
      ? TieBreak.none
      : date.compareTo('2019-10-14') < 0
      ? TieBreak.superOverThenBoundaryCount
      : TieBreak.superOverRepeat;
  final MatchRules rules;
  if (matchType == 'Test') {
    rules = MatchRules.test.copyWith(playersPerSide: a.players.length);
  } else {
    final overs = info['overs'] as int? ?? (matchType == 'ODI' ? 50 : 20);
    final base = bpo == 5
        ? MatchRules.hundred
        : matchType == 'ODI'
        ? MatchRules.odi
        : MatchRules.t20;
    // The no-ball penalty is whatever value the data uses most.
    final noBallValues = <int, int>{};
    for (final inn in inningsData) {
      for (final o in (inn['overs'] as List).cast<Map<String, dynamic>>()) {
        for (final d
            in (o['deliveries'] as List).cast<Map<String, dynamic>>()) {
          final nb = (d['extras'] as Map?)?['noballs'] as int?;
          if (nb != null) {
            noBallValues.update(nb, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      }
    }
    // The penalty is the smallest value; larger ones include runs taken.
    final noBallRuns = noBallValues.isEmpty
        ? base.noBallRuns
        : noBallValues.keys.reduce((x, y) => x < y ? x : y);
    rules = base.copyWith(
      noBallRuns: noBallRuns,
      playersPerSide: a.players.length,
      ballsPerInnings: overs * bpo,
      // Free hits followed every no-ball from July 2015; before that only
      // front-foot no-balls, which the data does not distinguish.
      freeHitAfterNoBall: date.compareTo('2015-07-05') >= 0,
      tieBreak: tieBreak,
    );
  }

  final toss = info['toss'] as Map<String, dynamic>;
  final firstBatting = inningsData.first['team'] as String;
  final setup = MatchSetup(
    rules: rules,
    teamA: a,
    teamB: b,
    toss: Toss(wonByTeamId: firstBatting, decision: TossDecision.bat),
  );
  replay.setup = setup;
  final problems = setup.validate();
  if (problems.isNotEmpty) {
    replay.skipped = problems.join(' ');
    return;
  }
  if (toss['winner'] != firstBatting && toss['decision'] == 'bat' ||
      toss['winner'] == firstBatting && toss['decision'] == 'field') {
    replay._correct('toss recorded differently');
  }

  final rain = outcome['method'] == 'D/L' || outcome['method'] == 'DLS';
  final scorer = Scorer(setup);
  // Match-long substitutions by incoming player, until applied.
  final lateSubs = <String, Map<String, dynamic>>{};
  final appliedSubs = <String>{};
  for (final inn in inningsData) {
    for (final over in (inn['overs'] as List).cast<Map<String, dynamic>>()) {
      for (final d
          in (over['deliveries'] as List).cast<Map<String, dynamic>>()) {
        final repl = d['replacements'] as Map<String, dynamic>?;
        for (final r
            in ((repl?['match'] as List?) ?? const [])
                .cast<Map<String, dynamic>>()) {
          lateSubs[id(r['in'] as String)] = r;
        }
      }
    }
  }
  void add(MatchEvent e, String where) {
    try {
      scorer.apply(e);
    } on IllegalEventException catch (err) {
      final freeHit =
          err.code == IllegalEventCode.dismissalNotAllowed &&
          err.message.contains('free hit');
      throw _Abort(
        '${freeHit ? 'free-hit conflict, ' : ''}$where: ${e.runtimeType} refused: ${err.message}',
      );
    }
    replay.events.add(e);
  }

  for (var ii = 0; ii < inningsData.length; ii++) {
    final inn = inningsData[ii];
    final team = inn['team'] as String;
    final where0 = 'innings ${ii + 1} ($team)';
    if (scorer.live.matchOver) {
      throw _Abort('$where0: engine already finished the match');
    }
    if (scorer.live.awaitingFollowOn) {
      final second = inningsData[1]['team'] as String;
      add(FollowOn(enforce: team == second), where0);
    }
    if (scorer.live.inningsCount != ii + 1) {
      throw _Abort('$where0: engine is on innings ${scorer.live.inningsCount}');
    }
    // A follow-on below the usual margin means time was lost and the
    // officials reduced it (Law 14.1.3).
    if (ii == 1 &&
        rules.isTwoInnings &&
        inningsData.length > 2 &&
        inningsData[2]['team'] == team) {
      add(const FollowOnMarginSet(1), where0);
      replay._correct('follow-on margin reduced for lost time');
    }
    final penalty = inn['penalty_runs'] as Map<String, dynamic>?;
    if (penalty?['pre'] case final int pre) {
      add(PenaltyRuns(teamId: team, runs: pre), where0);
    }
    if (inn['forfeited'] == true) {
      add(const Forfeit(), where0);
      continue;
    }
    final target = inn['target'] as Map<String, dynamic>?;
    // A D/L target set during the chase is not replayed: the data does not
    // say when it was set. One set after a shortened first innings is.
    final limit = rules.ballsPerInnings;
    final first = ii == 1 && limit != null
        ? scorer.snapshot().innings.first
        : null;
    final firstShortened =
        first != null &&
        first.legalBalls < limit! &&
        first.endReason != InningsEndReason.allOut;
    if (target != null &&
        (!rain || firstShortened) &&
        inn['super_over'] != true &&
        rules.ballsPerInnings != null) {
      final runs = target['runs'] as int?;
      final overs = target['overs'] as num?;
      final balls = overs == null
          ? null
          : (overs.floor() * bpo + ((overs - overs.floor()) * 10).round());
      final reviseBalls = balls != null && balls != scorer.currentBallLimit
          ? balls
          : null;
      final reviseRuns = runs != null && runs != scorer.currentTarget
          ? runs
          : null;
      if (reviseBalls != null || reviseRuns != null) {
        add(
          RevisedTarget(ballsPerInnings: reviseBalls, target: reviseRuns),
          where0,
        );
      }
    }

    final overs = (inn['overs'] as List).cast<Map<String, dynamic>>();
    for (final over in overs) {
      final overNo = over['over'] as int;
      final deliveries = (over['deliveries'] as List)
          .cast<Map<String, dynamic>>();
      for (var di = 0; di < deliveries.length; di++) {
        final d = deliveries[di];
        final where = '$where0 ball ${d['actual_delivery'] ?? '$overNo.$di'}';
        final batter = id(d['batter'] as String);
        final nonStriker = id(d['non_striker'] as String);
        final bowler = id(d['bowler'] as String);

        // Match-long replacements happen before the ball.
        final repl = d['replacements'] as Map<String, dynamic>?;
        for (final r
            in ((repl?['match'] as List?) ?? const [])
                .cast<Map<String, dynamic>>()) {
          final inId = id(r['in'] as String);
          lateSubs.remove(inId);
          if (!appliedSubs.add(inId)) continue;
          final out = id(r['out'] as String);
          final live = scorer.live;
          if (!live.inningsClosed &&
              (live.striker == out || live.nonStriker == out)) {
            add(Retired(out, out: false), where);
            replay._correct('retired before substitution');
          }
          add(
            Substitute(
              outPlayerId: out,
              inPlayerId: id(r['in'] as String),
              reason: switch (r['reason']) {
                'concussion_substitute' => SubstitutionReason.concussion,
                'impact_player' => SubstitutionReason.impactPlayer,
                _ => SubstitutionReason.other,
              },
            ),
            where,
          );
        }

        // Substitutions are sometimes recorded after the substitute has
        // already appeared; apply them when the player is first needed.
        for (final p in [batter, nonStriker, bowler]) {
          final pending = lateSubs.remove(p);
          if (pending != null) {
            final out = id(pending['out'] as String);
            final live = scorer.live;
            if (!live.inningsClosed &&
                (live.striker == out || live.nonStriker == out)) {
              add(Retired(out, out: false), where);
            }
            add(
              Substitute(
                outPlayerId: out,
                inPlayerId: p,
                reason: switch (pending['reason']) {
                  'concussion_substitute' => SubstitutionReason.concussion,
                  'impact_player' => SubstitutionReason.impactPlayer,
                  _ => SubstitutionReason.other,
                },
              ),
              where,
            );
            appliedSubs.add(p);
            replay._correct('substitution recorded late');
          }
        }

        // Miscounted overs (Law 17.5).
        var live = scorer.live;
        if (live.completedOvers == overNo + 1 &&
            live.bowler == null &&
            di > 0) {
          add(const OverExtended(), where);
          replay._correct('over extended by umpire');
        } else if (overNo > live.completedOvers &&
            live.currentOverDeliveries > 0) {
          add(const OverCalledEarly(), where);
          replay._correct('over called early by umpire');
        }

        live = scorer.live;
        if (!live.openersSet) {
          add(
            OpenersSelected(strikerId: batter, nonStrikerId: nonStriker),
            where,
          );
        }
        live = scorer.live;
        for (final atCrease in [live.striker, live.nonStriker]) {
          if (atCrease != null &&
              atCrease != batter &&
              atCrease != nonStriker) {
            // Left the field without the data saying so: retired hurt.
            add(Retired(atCrease, out: false), where);
            replay._correct('unrecorded retirement');
          }
        }
        while (scorer.live.hasVacancy) {
          live = scorer.live;
          final incoming = [batter, nonStriker].firstWhere(
            (p) => p != live.striker && p != live.nonStriker,
            orElse: () => throw _Abort('$where: no batter to fill the vacancy'),
          );
          add(BatterIn(incoming), where);
        }
        live = scorer.live;
        if (live.striker == nonStriker && live.nonStriker == batter) {
          add(const SwapStrike(), where);
          replay._correct('strike swapped');
        }
        if (scorer.live.bowler != bowler) {
          add(BowlerSelected(bowler), where);
        }

        add(_delivery(d, id, rules, replay), where);

        final extras = d['extras'] as Map<String, dynamic>?;
        if (extras?['penalty'] case final int p when p > 0) {
          add(PenaltyRuns(teamId: team, runs: p), where);
        }
        for (final w
            in ((d['wickets'] as List?) ?? const [])
                .cast<Map<String, dynamic>>()
                .skip(_hasDeliveryDismissal(d) ? 1 : 0)) {
          final kind = w['kind'] as String;
          final out = id(w['player_out'] as String);
          final live = scorer.live;
          if (live.inningsClosed) continue;
          if (kind != 'timed out' &&
              out != live.striker &&
              out != live.nonStriker) {
            continue;
          }
          if (kind == 'retired hurt' || kind == 'retired not out') {
            add(Retired(out, out: false), where);
          } else if (kind == 'retired out') {
            add(Retired(out, out: true), where);
          } else if (kind == 'timed out') {
            add(TimedOut(out), where);
          } else {
            throw _Abort('$where: second dismissal "$kind" on one ball');
          }
        }
      }
    }

    if (penalty?['post'] case final int post) {
      add(PenaltyRuns(teamId: team, runs: post), '$where0 end');
    }
    final live = scorer.live;
    final lastInnings = ii == inningsData.length - 1;
    if (live.inningsCount == ii + 1 && !live.inningsClosed && !live.matchOver) {
      if (inn['declared'] == true) {
        add(const Declare(), '$where0 end');
      } else if (lastInnings &&
          (outcome['result'] == 'draw' ||
              outcome['result'] == 'no result' ||
              rain)) {
        // The match ended during this innings; handled below.
      } else {
        add(const EndInnings(), '$where0 end');
        replay._correct('innings closed without all out (absent or retired)');
      }
    }
  }

  if (!scorer.live.matchOver) {
    if (outcome['result'] == 'draw') {
      add(const Drawn(), 'end');
    } else if (outcome['result'] == 'no result') {
      add(const Abandoned(), 'end');
    } else if (rain) {
      // Decided on a par score; the engine cannot compute that itself.
      add(const Abandoned(), 'end');
      replay._correct('result on a rain par score');
    }
  }

  final state = scorer.snapshot();
  replay.state = state;
  _compare(replay, inningsData, outcome, state, rain);
}

bool _hasDeliveryDismissal(Map<String, dynamic> d) {
  final wickets = (d['wickets'] as List?) ?? const [];
  return wickets.isNotEmpty &&
      _deliveryDismissals.containsKey((wickets.first as Map)['kind']);
}

Delivery _delivery(
  Map<String, dynamic> d,
  String Function(String) id,
  MatchRules rules,
  CricsheetReplay replay,
) {
  final runs = d['runs'] as Map<String, dynamic>;
  final extras = (d['extras'] as Map<String, dynamic>?) ?? const {};
  final batterRuns = runs['batter'] as int;
  final nonBoundary = runs['non_boundary'] == true;
  final wides = extras['wides'] as int? ?? 0;
  final noBalls = extras['noballs'] as int? ?? 0;
  final byes = extras['byes'] as int? ?? 0;
  final legByes = extras['legbyes'] as int? ?? 0;

  // On a wicket ball runs can only have been run, never a boundary.
  final wicketBall = _hasDeliveryDismissal(d);
  (int, int) split(int r) =>
      (r == 4 || r == 6) && !nonBoundary && !wicketBall ? (0, r) : (r, 0);

  Dismissal? dismissal;
  if (_hasDeliveryDismissal(d)) {
    final w = (d['wickets'] as List).first as Map<String, dynamic>;
    final kindName = w['kind'] as String;
    final fielders = ((w['fielders'] as List?) ?? const [])
        .cast<Map<String, dynamic>>();
    String? fielder = kindName == 'caught and bowled'
        ? id(d['bowler'] as String)
        : fielders
              .where((f) => f['name'] != null)
              .map((f) => id(f['name'] as String))
              .firstOrNull;
    final squad = replay.setup!.teamA.squad.followedBy(
      replay.setup!.teamB.squad,
    );
    if (fielder != null && !squad.any((p) => p.id == fielder)) fielder = null;
    dismissal = Dismissal(
      kind: _deliveryDismissals[kindName]!,
      batterId: id(w['player_out'] as String),
      fielderId: fielder,
    );
  }

  if (wides > 0) {
    // Some older records credit runs on a wide to the batter.
    final taken = wides - rules.wideRuns + batterRuns;
    final (completed, boundary) = taken == 4 && !wicketBall
        ? (0, 4)
        : (taken, 0);
    return Delivery(
      kind: DeliveryKind.wide,
      completedRuns: completed,
      boundary: boundary,
      dismissal: dismissal,
    );
  }
  final kind = noBalls > 0 ? DeliveryKind.noBall : DeliveryKind.legal;
  if (noBalls > rules.noBallRuns) {
    // Older records count runs taken off a no-ball as no-balls.
    replay._correct('no-ball runs recorded as no-balls');
  }
  final extraRun = noBalls > rules.noBallRuns ? noBalls - rules.noBallRuns : 0;
  if (byes + extraRun > 0) {
    final (c, b) = split(byes + extraRun);
    return Delivery(
      kind: kind,
      runsTo: RunsTo.byes,
      completedRuns: c,
      boundary: b,
      dismissal: dismissal,
    );
  }
  if (legByes > 0) {
    final (c, b) = split(legByes);
    return Delivery(
      kind: kind,
      runsTo: RunsTo.legByes,
      completedRuns: c,
      boundary: b,
      dismissal: dismissal,
    );
  }
  final (c, b) = split(batterRuns);
  return Delivery(
    kind: kind,
    completedRuns: c,
    boundary: b,
    dismissal: dismissal,
  );
}

void _compare(
  CricsheetReplay replay,
  List<Map<String, dynamic>> inningsData,
  Map<String, dynamic> outcome,
  MatchState state,
  bool rain,
) {
  for (var i = 0; i < inningsData.length; i++) {
    final inn = inningsData[i];
    final deliveries = [
      for (final o in (inn['overs'] as List).cast<Map<String, dynamic>>())
        ...(o['deliveries'] as List).cast<Map<String, dynamic>>(),
    ];
    final penalty = inn['penalty_runs'] as Map<String, dynamic>? ?? const {};
    final runs =
        deliveries.fold<int>(
          0,
          (s, d) => s + ((d['runs'] as Map)['total'] as int),
        ) +
        ((penalty['pre'] as int?) ?? 0) +
        ((penalty['post'] as int?) ?? 0);
    final wickets = deliveries
        .expand(
          (d) => ((d['wickets'] as List?) ?? const [])
              .cast<Map<String, dynamic>>(),
        )
        .where(
          (w) => w['kind'] != 'retired hurt' && w['kind'] != 'retired not out',
        )
        .length;
    final legal = deliveries.where((d) {
      final e = d['extras'] as Map<String, dynamic>?;
      return e == null || (e['wides'] == null && e['noballs'] == null);
    }).length;
    if (i >= state.innings.length) {
      replay.mismatches.add('innings ${i + 1} missing from the engine');
      continue;
    }
    final mine = state.innings[i];
    final label = 'innings ${i + 1}';
    if (mine.runs != runs) {
      replay.mismatches.add('$label runs ${mine.runs} vs $runs');
    }
    if (mine.wickets != wickets) {
      replay.mismatches.add('$label wickets ${mine.wickets} vs $wickets');
    }
    if (mine.legalBalls != legal) {
      replay.mismatches.add('$label balls ${mine.legalBalls} vs $legal');
    }
  }
  final extra = state.innings
      .skip(inningsData.length)
      .where((i) => i.legalBalls > 0 || i.runs > 0 || i.batters.isNotEmpty);
  if (extra.isNotEmpty) {
    replay.mismatches.add(
      'engine has ${state.innings.length} innings, data ${inningsData.length}',
    );
  }

  final result = state.result;
  final winner = (outcome['eliminator'] ?? outcome['winner']) as String?;
  final by = outcome['by'] as Map<String, dynamic>?;
  if (outcome['result'] == 'draw') {
    if (result is! Draw) {
      replay.mismatches.add('result: expected a draw, got $result');
    }
  } else if (outcome['result'] == 'no result' || rain) {
    return;
  } else if (outcome['result'] == 'tie' && winner == null) {
    if (result is! Tie) {
      replay.mismatches.add(
        'result: expected a tie, got ${result?.describe(state.setup)}',
      );
    }
  } else if (winner != null) {
    if (result is! Win || result.winnerTeamId != winner) {
      replay.mismatches.add(
        'result: expected $winner to win, got ${result?.describe(state.setup)}',
      );
      return;
    }
    if (outcome['eliminator'] != null || by == null) return;
    final margin = result.margin;
    final ok = switch (margin) {
      ByInningsAndRuns(:final runs) => by['innings'] == 1 && by['runs'] == runs,
      ByRuns(:final runs) => by['innings'] == null && by['runs'] == runs,
      ByWickets(:final wickets) => by['wickets'] == wickets,
      _ => true,
    };
    if (!ok) {
      replay.mismatches.add('margin: ${result.describe(state.setup)} vs $by');
    }
  }
}
