import 'dart:math' as math;

import '../model/events.dart';
import '../model/match_setup.dart';
import '../rules/match_rules.dart';
import '../state/cards.dart';
import '../state/innings_state.dart';
import '../state/match_state.dart';
import '../state/pending.dart';
import '../state/result.dart';
import 'errors.dart';

/// Applies events one at a time and keeps the running match state.
///
/// Internal and mutable; [MatchState] snapshots are what callers see.
final class Scorer {
  Scorer(this.setup) {
    _startInnings(
      kind: InningsKind.regular,
      battingTeamId: setup.battingFirstTeamId,
      ballLimit: rules.ballsPerInnings,
    );
  }

  final MatchSetup setup;
  final List<_Innings> _innings = [];
  MatchResult? _result;

  MatchRules get rules => setup.rules;

  // ---------------------------------------------------------------- events

  void apply(MatchEvent event) {
    if (_result != null) {
      throw const IllegalEventException(
        IllegalEventCode.matchOver,
        'The match is over.',
      );
    }
    switch (event) {
      case OpenersSelected():
        _openers(event);
      case BowlerSelected():
        _selectBowler(event.bowlerId);
      case BatterIn():
        _batterIn(event.batterId);
      case SwapStrike():
        _swapStrike();
      case Retired():
        _retire(event.batterId, out: event.out);
      case TimedOut():
        _timedOut(event.batterId);
      case RevisedTarget():
        _revise(event);
      case EndInnings():
        _close(_open, InningsEndReason.closed);
      case RunOutBeforeDelivery():
        _runOutBeforeDelivery(event);
      case Abandoned():
        final inn = _current;
        inn.end ??= InningsEndReason.closed;
        inn.bowler = null;
        _result = const NoResult();
      case Delivery():
        _delivery(event);
    }
  }

  _Innings get _current => _innings.last;

  _Innings get _open {
    final inn = _current;
    if (inn.end != null) {
      throw const IllegalEventException(
        IllegalEventCode.inningsClosed,
        'The innings has ended.',
      );
    }
    return inn;
  }

  void _openers(OpenersSelected e) {
    final inn = _open;
    if (inn.openersSet) {
      throw const IllegalEventException(
        IllegalEventCode.openersAlreadyChosen,
        'The openers are already in.',
      );
    }
    if (e.strikerId == e.nonStrikerId) {
      throw const IllegalEventException(
        IllegalEventCode.samePlayer,
        'Choose two different openers.',
      );
    }
    for (final id in [e.strikerId, e.nonStrikerId]) {
      _requireCandidate(inn, id);
    }
    inn.openersSet = true;
    inn.striker = inn.addBatter(e.strikerId).id;
    inn.nonStriker = inn.addBatter(e.nonStrikerId).id;
    inn.partnerships.add(_Partnership([e.strikerId, e.nonStrikerId]));
  }

  void _selectBowler(String id) {
    final inn = _open;
    _requireOpeners(inn);
    if (!setup.team(inn.bowlingTeamId).hasPlayer(id)) {
      throw IllegalEventException(
        IllegalEventCode.notInBowlingTeam,
        '${_name(id)} is not in the fielding side.',
      );
    }
    final current = inn.currentOver;
    final midOver = current != null && current.deliveries.isNotEmpty;
    final reason = _bowlerIneligibility(inn, id, midOver: midOver);
    if (reason != null) {
      throw IllegalEventException(
        IllegalEventCode.bowlerIneligible,
        '${_name(id)} cannot bowl: ${_ineligibilityText(reason)}.',
      );
    }
    if (current == null) {
      inn.overs.add(_Over(inn.completedOvers + 1)..bowlers.add(id));
    } else if (midOver) {
      current.bowlers.add(id);
    } else {
      current.bowlers
        ..clear()
        ..add(id);
    }
    inn.bowler = id;
    inn.bowlers.putIfAbsent(id, () => _Bowler(id));
  }

  void _batterIn(String id) {
    final inn = _open;
    _requireOpeners(inn);
    if (!inn.hasVacancy) {
      throw const IllegalEventException(
        IllegalEventCode.noVacancy,
        'Both batters are already in.',
      );
    }
    _requireCandidate(inn, id);
    final batter = inn.batters[id];
    if (batter != null) {
      batter
        ..status = BatterStatus.batting
        ..returned = true;
    } else {
      inn.addBatter(id);
    }
    if (inn.striker == null) {
      inn.striker = id;
    } else {
      inn.nonStriker = id;
    }
    inn.partnerships.add(_Partnership([inn.striker!, inn.nonStriker!]));
  }

  void _swapStrike() {
    final inn = _open;
    if (inn.striker == null || inn.nonStriker == null) {
      throw const IllegalEventException(
        IllegalEventCode.cannotSwapStrike,
        'Strike can only be swapped with two batters in.',
      );
    }
    inn.swapEnds();
  }

  void _retire(String id, {required bool out}) {
    final inn = _open;
    if (id != inn.striker && id != inn.nonStriker) {
      throw IllegalEventException(
        IllegalEventCode.notAtCrease,
        '${_name(id)} is not batting.',
      );
    }
    final batter = inn.batters[id]!;
    if (out) {
      _recordWicket(
        inn,
        batter,
        const DismissalRecord(kind: DismissalKind.retiredOut),
      );
    } else {
      batter.status = BatterStatus.retiredNotOut;
    }
    inn.vacate(id);
    _afterChange(inn);
  }

  void _timedOut(String id) {
    final inn = _open;
    _requireOpeners(inn);
    if (!inn.hasVacancy) {
      throw const IllegalEventException(
        IllegalEventCode.noVacancy,
        'No batter is due in.',
      );
    }
    _requireCandidate(inn, id);
    if (inn.batters.containsKey(id)) {
      throw IllegalEventException(
        IllegalEventCode.batterUnavailable,
        '${_name(id)} has already batted.',
      );
    }
    final batter = inn.addBatter(id);
    _recordWicket(
      inn,
      batter,
      const DismissalRecord(kind: DismissalKind.timedOut),
    );
    _afterChange(inn);
  }

  /// Law 38.3: the non-striker is run out by the bowler before the ball is
  /// bowled. Not a delivery, and not credited to the bowler.
  void _runOutBeforeDelivery(RunOutBeforeDelivery e) {
    final inn = _open;
    _requireOpeners(inn);
    if (inn.hasVacancy) {
      throw const IllegalEventException(
        IllegalEventCode.batterNeeded,
        'A new batter needs to come in first.',
      );
    }
    if (inn.bowler == null) {
      throw const IllegalEventException(
        IllegalEventCode.bowlerNeeded,
        'Choose the bowler for this over first.',
      );
    }
    if (e.batterId != inn.nonStriker) {
      throw IllegalEventException(
        IllegalEventCode.wrongBatterOut,
        'Only the non-striker can be run out before the ball is bowled; '
        '${_name(e.batterId)} is not the non-striker.',
      );
    }
    final batter = inn.batters[e.batterId]!;
    _recordWicket(
      inn,
      batter,
      DismissalRecord(kind: DismissalKind.runOut, fielderId: inn.bowler),
    );
    inn.vacate(batter.id);
    _afterChange(inn);
  }

  void _revise(RevisedTarget e) {
    final inn = _open;
    if (inn.kind != InningsKind.regular) {
      throw const IllegalEventException(
        IllegalEventCode.invalidRevision,
        'Super overs cannot be shortened.',
      );
    }
    final balls = e.ballsPerInnings;
    if (balls != null) {
      if (balls < 1 || balls < inn.legalBalls) {
        throw IllegalEventException(
          IllegalEventCode.invalidRevision,
          'The innings already has '
          '${formatOvers(inn.legalBalls, rules.ballsPerOver)} overs bowled.',
        );
      }
      inn.ballLimit = balls;
    }
    final target = e.target;
    if (target != null) {
      if (inn.target == null) {
        throw const IllegalEventException(
          IllegalEventCode.invalidRevision,
          'A target can only be set for the side batting second.',
        );
      }
      if (target < 1) {
        throw const IllegalEventException(
          IllegalEventCode.invalidRevision,
          'The target must be at least 1 run.',
        );
      }
      inn
        ..target = target
        ..revisedTarget = true;
    }
    _afterChange(inn);
  }

  void _delivery(Delivery d) {
    final inn = _open;
    _requireOpeners(inn);
    if (inn.hasVacancy) {
      throw const IllegalEventException(
        IllegalEventCode.batterNeeded,
        'A new batter needs to come in first.',
      );
    }
    final bowlerId = inn.bowler;
    if (bowlerId == null) {
      throw const IllegalEventException(
        IllegalEventCode.bowlerNeeded,
        'Choose the bowler for this over first.',
      );
    }
    final freeHit = inn.freeHitNext;
    _validateDelivery(inn, d, freeHit: freeHit);

    final striker = inn.batters[inn.striker!]!;
    final bowler = inn.bowlers[bowlerId]!;
    final over = inn.currentOver!;
    var teamRuns = 0;
    var bowlerRuns = 0;

    void addRunsPart() {
      final r = d.runs;
      switch (d.runsTo) {
        case RunsTo.batter:
          striker.runs += r;
          bowlerRuns += r;
          if (d.boundary == 4) striker.fours++;
          if (d.boundary == 6) striker.sixes++;
        case RunsTo.byes:
          inn.byes += r;
        case RunsTo.legByes:
          inn.legByes += r;
      }
      teamRuns += r;
    }

    switch (d.kind) {
      case DeliveryKind.wide:
        final w = rules.wideRuns + d.runs;
        inn.wides += w;
        teamRuns += w;
        bowlerRuns += w;
        bowler.wides++;
      case DeliveryKind.noBall:
        inn.noBalls += rules.noBallRuns;
        teamRuns += rules.noBallRuns;
        bowlerRuns += rules.noBallRuns;
        bowler.noBalls++;
        addRunsPart();
      case DeliveryKind.legal:
        addRunsPart();
    }

    if (d.kind != DeliveryKind.wide) striker.balls++;
    if (d.isLegal) {
      bowler.legalBalls++;
      inn.legalBalls++;
      over.legalBalls++;
      if (bowlerRuns == 0) bowler.dots++;
    }
    bowler.runs += bowlerRuns;
    over.bowlerRuns += bowlerRuns;
    inn.runs += teamRuns;
    final partnership = inn.partnerships.last;
    partnership.runs += teamRuns;
    if (d.kind != DeliveryKind.wide) partnership.balls++;

    over.deliveries.add(
      DeliveryRecord(
        delivery: d,
        bowlerId: bowlerId,
        strikerId: striker.id,
        teamRuns: inn.runs,
        totalRuns: teamRuns,
        wasFreeHit: freeHit,
      ),
    );

    // Ends after running. A boundary allowance does not change ends.
    if (!inn.alone && d.completedRuns.isOdd) inn.swapEnds();

    final dismissal = d.dismissal;
    if (dismissal != null) {
      if (!inn.alone &&
          dismissal.kind == DismissalKind.runOut &&
          dismissal.crossed) {
        inn.swapEnds();
      }
      final out = inn.batters[dismissal.batterId]!;
      _recordWicket(
        inn,
        out,
        DismissalRecord(
          kind: dismissal.kind,
          bowlerId: dismissal.kind.creditedToBowler ? bowlerId : null,
          fielderId: dismissal.fielderId,
        ),
      );
      if (dismissal.kind.creditedToBowler) bowler.wickets++;
      inn.vacate(out.id);
    }

    if (rules.freeHitAfterNoBall && d.kind == DeliveryKind.noBall) {
      inn.freeHitNext = true;
    } else if (d.isLegal) {
      inn.freeHitNext = false;
    }

    if (d.isLegal && over.legalBalls == rules.ballsPerOver) {
      over.complete = true;
      if (over.bowlers.length == 1 && over.bowlerRuns == 0) bowler.maidens++;
      inn.bowler = null;
      if (!inn.alone && inn.completedOvers % rules.oversPerEnd == 0) {
        inn.swapEnds();
      }
    }

    _afterChange(inn);
  }

  // ------------------------------------------------------------ validation

  void _validateDelivery(_Innings inn, Delivery d, {required bool freeHit}) {
    void fail(String message) =>
        throw IllegalEventException(IllegalEventCode.invalidDelivery, message);

    if (d.completedRuns < 0) fail('Runs cannot be negative.');
    if (d.boundary != 0 && d.boundary != 4 && d.boundary != 6) {
      fail('A boundary is worth 4 or 6.');
    }
    if (d.kind == DeliveryKind.wide && d.runsTo != RunsTo.batter) {
      fail('All runs from a wide are wides, not byes or leg byes.');
    }
    if (d.boundary == 6 &&
        (d.kind == DeliveryKind.wide || d.runsTo != RunsTo.batter)) {
      fail('Six runs can only be scored off the bat.');
    }

    final dismissal = d.dismissal;
    if (dismissal == null) return;
    final kind = dismissal.kind;
    final allowed = _allowedDismissals(d.kind, freeHit: freeHit);
    if (!allowed.contains(kind)) {
      final on = freeHit
          ? 'a free hit'
          : switch (d.kind) {
              DeliveryKind.wide => 'a wide',
              DeliveryKind.noBall => 'a no-ball',
              DeliveryKind.legal => 'this delivery',
            };
      throw IllegalEventException(
        IllegalEventCode.dismissalNotAllowed,
        '${_dismissalText(kind)} is not possible off $on.',
      );
    }
    final id = dismissal.batterId;
    if (id != inn.striker && id != inn.nonStriker) {
      throw IllegalEventException(
        IllegalEventCode.wrongBatterOut,
        '${_name(id)} is not batting.',
      );
    }
    if (kind.strikerOnly && id != inn.striker) {
      throw IllegalEventException(
        IllegalEventCode.wrongBatterOut,
        'Only the striker can be out ${_dismissalText(kind).toLowerCase()}.',
      );
    }
    if (kind.endsDeliveryWithoutRuns && d.runs != 0) {
      fail(
        'No runs can be scored when a batter is ${_dismissalText(kind).toLowerCase()}.',
      );
    }
    if (d.boundary != 0) fail('A boundary cannot be scored on a wicket ball.');
    final target = inn.target;
    if (target != null) {
      final penalty = switch (d.kind) {
        DeliveryKind.wide => rules.wideRuns,
        DeliveryKind.noBall => rules.noBallRuns,
        DeliveryKind.legal => 0,
      };
      if (inn.runs + penalty + d.runs >= target) {
        fail(
          'The target was reached before the wicket, so the match was '
          'already over. Record the runs without the wicket.',
        );
      }
    }
    final fielder = dismissal.fielderId;
    if (fielder != null && !setup.team(inn.bowlingTeamId).hasPlayer(fielder)) {
      throw IllegalEventException(
        IllegalEventCode.notInBowlingTeam,
        '${_name(fielder)} is not in the fielding side.',
      );
    }
  }

  /// Dismissals possible on a delivery (Laws 21.18, 22.1, 32-40 and the
  /// free-hit playing condition).
  Set<DismissalKind> _allowedDismissals(
    DeliveryKind kind, {
    required bool freeHit,
  }) {
    const noBallSet = {
      DismissalKind.runOut,
      DismissalKind.obstructingTheField,
      DismissalKind.hitTheBallTwice,
    };
    var allowed = switch (kind) {
      DeliveryKind.legal => {
        DismissalKind.bowled,
        DismissalKind.caught,
        DismissalKind.lbw,
        DismissalKind.stumped,
        DismissalKind.hitWicket,
        DismissalKind.runOut,
        DismissalKind.obstructingTheField,
        DismissalKind.hitTheBallTwice,
      },
      DeliveryKind.wide => {
        DismissalKind.stumped,
        DismissalKind.hitWicket,
        DismissalKind.runOut,
        DismissalKind.obstructingTheField,
      },
      DeliveryKind.noBall => noBallSet,
    };
    if (freeHit) allowed = allowed.intersection(noBallSet);
    if (!rules.lbwAllowed) allowed.remove(DismissalKind.lbw);
    return allowed;
  }

  /// Dismissals the scorer can choose for the next delivery of [kind].
  Set<DismissalKind> allowedDismissals(DeliveryKind kind) {
    final inn = _current;
    return _allowedDismissals(kind, freeHit: inn.freeHitNext);
  }

  void _requireOpeners(_Innings inn) {
    if (!inn.openersSet) {
      throw const IllegalEventException(
        IllegalEventCode.openersNeeded,
        'Choose the opening batters first.',
      );
    }
  }

  void _requireCandidate(_Innings inn, String id) {
    if (!setup.team(inn.battingTeamId).hasPlayer(id)) {
      throw IllegalEventException(
        IllegalEventCode.notInBattingTeam,
        '${_name(id)} is not in the batting side.',
      );
    }
    if (!_batterCandidates(inn).contains(id)) {
      throw IllegalEventException(
        IllegalEventCode.batterUnavailable,
        '${_name(id)} cannot bat now.',
      );
    }
  }

  // --------------------------------------------------------------- wickets

  void _recordWicket(_Innings inn, _Batter batter, DismissalRecord record) {
    batter
      ..status = BatterStatus.out
      ..dismissal = record;
    inn.wickets++;
    inn.fallOfWickets.add(
      FallOfWicket(
        wicket: inn.wickets,
        runs: inn.runs,
        batterId: batter.id,
        legalBalls: inn.legalBalls,
      ),
    );
  }

  // ------------------------------------------------- after every change

  void _afterChange(_Innings inn) {
    if (_checkEnd(inn)) return;
    _autoRetire(inn);
    if (inn.hasVacancy && _batterCandidates(inn).isEmpty) {
      final remaining = inn.striker ?? inn.nonStriker;
      if (rules.lastBatterCanBatAlone &&
          remaining != null &&
          inn.kind == InningsKind.regular) {
        inn
          ..alone = true
          ..striker = remaining
          ..nonStriker = null;
        if (inn.partnerships.last.ids.length == 2) {
          inn.partnerships.add(_Partnership([remaining]));
        }
      } else {
        _close(inn, InningsEndReason.allOut);
      }
    }
  }

  /// Closes the innings if it is over. Returns true when it closed.
  bool _checkEnd(_Innings inn) {
    if (inn.end != null) return true;
    final InningsEndReason? reason;
    if (inn.wickets >= inn.maxWickets) {
      reason = InningsEndReason.allOut;
    } else if (inn.target != null && inn.runs >= inn.target!) {
      reason = InningsEndReason.targetReached;
    } else if (inn.ballLimit != null && inn.legalBalls >= inn.ballLimit!) {
      reason = InningsEndReason.ballsComplete;
    } else {
      reason = null;
    }
    if (reason == null) return false;
    _close(inn, reason);
    return true;
  }

  void _autoRetire(_Innings inn) {
    final limit = rules.retireAtRuns;
    if (limit == null) return;
    for (final id in [inn.striker, inn.nonStriker]) {
      if (id == null) continue;
      final b = inn.batters[id]!;
      if (b.returned || b.runs < limit) continue;
      if (_batterCandidates(inn).isEmpty) return;
      b.status = BatterStatus.retiredNotOut;
      inn.vacate(id);
    }
  }

  void _close(_Innings inn, InningsEndReason reason) {
    if (inn.end != null) return;
    inn.end = reason;
    inn.bowler = null;
    _afterInningsClosed(inn);
  }

  // ------------------------------------------------- innings and result

  void _startInnings({
    required InningsKind kind,
    required String battingTeamId,
    required int? ballLimit,
    int? target,
    Set<String> barredBatters = const {},
    Set<String> barredBowlers = const {},
  }) {
    final superOver = kind == InningsKind.superOver;
    _innings.add(
      _Innings(
        number: _innings.length + 1,
        kind: kind,
        battingTeamId: battingTeamId,
        bowlingTeamId: setup.opponent(battingTeamId).id,
        ballLimit: superOver ? rules.ballsPerOver : ballLimit,
        maxWickets: superOver
            ? math.min(2, rules.playersPerSide - 1)
            : rules.maxWickets,
        target: target,
        barredBatters: barredBatters,
        barredBowlers: barredBowlers,
      ),
    );
  }

  void _afterInningsClosed(_Innings inn) {
    if (_result != null) return;
    if (inn.kind == InningsKind.regular) {
      if (inn.number == 1) {
        _startInnings(
          kind: InningsKind.regular,
          battingTeamId: inn.bowlingTeamId,
          ballLimit: inn.ballLimit,
          target: inn.runs + 1,
        );
        return;
      }
      _resolveChase(inn);
      return;
    }
    _resolveSuperOver(inn);
  }

  void _resolveChase(_Innings chase) {
    final target = chase.target!;
    if (chase.runs >= target) {
      _result = Win(
        winnerTeamId: chase.battingTeamId,
        margin: ByWickets(
          chase.maxWickets - chase.wickets,
          ballsRemaining: chase.ballLimit == null
              ? null
              : chase.ballLimit! - chase.legalBalls,
        ),
        revisedTarget: chase.revisedTarget,
      );
    } else if (chase.runs == target - 1) {
      if (rules.tieBreak == TieBreak.none) {
        _result = const Tie();
      } else {
        // The side batting second bats first in the super over.
        _startInnings(
          kind: InningsKind.superOver,
          battingTeamId: chase.battingTeamId,
          ballLimit: rules.ballsPerOver,
        );
      }
    } else {
      _result = Win(
        winnerTeamId: chase.bowlingTeamId,
        margin: ByRuns(target - 1 - chase.runs),
        revisedTarget: chase.revisedTarget,
      );
    }
  }

  void _resolveSuperOver(_Innings inn) {
    if (inn.target == null) {
      _startInnings(
        kind: InningsKind.superOver,
        battingTeamId: inn.bowlingTeamId,
        ballLimit: rules.ballsPerOver,
        target: inn.runs + 1,
        barredBatters: _previousSuperOver(inn.bowlingTeamId, batting: true),
        barredBowlers: _previousSuperOver(inn.battingTeamId, batting: false),
      );
      return;
    }
    final target = inn.target!;
    if (inn.runs >= target) {
      _result = Win(
        winnerTeamId: inn.battingTeamId,
        margin: const BySuperOver(),
      );
    } else if (inn.runs < target - 1) {
      _result = Win(
        winnerTeamId: inn.bowlingTeamId,
        margin: const BySuperOver(),
      );
    } else if (rules.tieBreak == TieBreak.superOverRepeat) {
      // The side batting second in this super over bats first in the next.
      _startInnings(
        kind: InningsKind.superOver,
        battingTeamId: inn.battingTeamId,
        ballLimit: rules.ballsPerOver,
        barredBatters: _dismissedIn(inn),
        barredBowlers: _bowledIn(inn),
      );
    } else {
      final a = _boundaries(inn.battingTeamId);
      final b = _boundaries(inn.bowlingTeamId);
      _result = a == b
          ? const Tie()
          : Win(
              winnerTeamId: a > b ? inn.battingTeamId : inn.bowlingTeamId,
              margin: ByBoundaryCount(
                winner: math.max(a, b),
                loser: math.min(a, b),
              ),
            );
    }
  }

  /// For the second innings of a repeated super over: who was dismissed
  /// (batting) or bowled (fielding) for [teamId] in the previous one.
  Set<String> _previousSuperOver(String teamId, {required bool batting}) {
    final supers = _innings
        .where((i) => i.kind == InningsKind.superOver)
        .toList();
    // The innings just finished is supers.last; look at the pair before it.
    if (supers.length < 3) return const {};
    final previousPair = supers.sublist(supers.length - 3, supers.length - 1);
    for (final i in previousPair) {
      if (batting && i.battingTeamId == teamId) return _dismissedIn(i);
      if (!batting && i.bowlingTeamId == teamId) return _bowledIn(i);
    }
    return const {};
  }

  Set<String> _dismissedIn(_Innings inn) => {
    for (final b in inn.batters.values)
      if (b.status == BatterStatus.out) b.id,
  };

  Set<String> _bowledIn(_Innings inn) => inn.bowlers.keys.toSet();

  int _boundaries(String teamId) => _innings
      .where((i) => i.battingTeamId == teamId)
      .fold(
        0,
        (sum, i) =>
            sum + i.batters.values.fold(0, (s, b) => s + b.fours + b.sixes),
      );

  // --------------------------------------------------------- candidates

  /// Players who may come in next: yet to bat, then retired not out.
  List<String> _batterCandidates(_Innings inn) {
    final team = setup.team(inn.battingTeamId);
    final yetToBat = [
      for (final p in team.players)
        if (!inn.batters.containsKey(p.id) && !inn.barredBatters.contains(p.id))
          p.id,
    ];
    final retired = [
      for (final b in inn.batters.values)
        if (b.status == BatterStatus.retiredNotOut &&
            !inn.barredBatters.contains(b.id))
          b.id,
    ];
    return [...yetToBat, ...retired];
  }

  int? _bowlerMaxBalls(_Innings inn) => inn.kind == InningsKind.superOver
      ? null
      : rules.bowlerLimit.maxBalls(
          inningsBalls: inn.ballLimit,
          ballsPerOver: rules.ballsPerOver,
        );

  BowlerIneligibility? _bowlerIneligibility(
    _Innings inn,
    String id, {
    required bool midOver,
  }) {
    if (inn.barredBowlers.contains(id)) {
      return BowlerIneligibility.bowledPreviousSuperOver;
    }
    if (midOver && inn.bowler == id) return BowlerIneligibility.currentBowler;

    final completed = inn.overs.where((o) => o.complete).toList();
    if (midOver) {
      // Law 17.8: the replacement must not have bowled the previous over.
      if (completed.isNotEmpty && completed.last.bowlers.contains(id)) {
        return BowlerIneligibility.bowledPreviousOver;
      }
    } else {
      var run = 0;
      for (final o in completed.reversed) {
        if (!o.bowlers.contains(id)) break;
        run++;
      }
      if (run >= rules.maxConsecutiveOversPerBowler) {
        return BowlerIneligibility.bowledPreviousOver;
      }
    }

    final max = _bowlerMaxBalls(inn);
    if (max != null) {
      final over = inn.currentOver;
      var needed = midOver
          ? rules.ballsPerOver - over!.legalBalls
          : rules.ballsPerOver;
      if (inn.ballLimit != null) {
        needed = math.min(needed, inn.ballLimit! - inn.legalBalls);
      }
      final bowled = inn.bowlers[id]?.legalBalls ?? 0;
      if (bowled + needed > max) return BowlerIneligibility.quotaReached;
    }
    return null;
  }

  ChooseBowler bowlerOptions({required bool midOver}) {
    final inn = _current;
    final eligible = <String>[];
    final ineligible = <String, BowlerIneligibility>{};
    for (final p in setup.team(inn.bowlingTeamId).players) {
      final reason = _bowlerIneligibility(inn, p.id, midOver: midOver);
      if (reason == null) {
        eligible.add(p.id);
      } else {
        ineligible[p.id] = reason;
      }
    }
    return ChooseBowler(
      bowlingTeamId: inn.bowlingTeamId,
      eligible: eligible,
      ineligible: ineligible,
      suggested: _suggestBowler(inn, eligible),
      midOver: midOver,
    );
  }

  String? _suggestBowler(_Innings inn, List<String> eligible) {
    if (eligible.isEmpty) return null;
    final completed = inn.overs.where((o) => o.complete).toList();
    // Bowlers usually alternate ends: suggest whoever bowled two overs ago.
    if (completed.length >= 2) {
      final candidate = completed[completed.length - 2].bowlers.last;
      if (eligible.contains(candidate)) return candidate;
    }
    for (final id in inn.bowlers.keys) {
      if (eligible.contains(id)) return id;
    }
    // Nobody has bowled yet: the specialist bowlers usually bat last.
    return eligible.last;
  }

  // -------------------------------------------------------- snapshots

  MatchState snapshot() {
    return MatchState(
      setup: setup,
      innings: [for (final inn in _innings) _snapshotInnings(inn)],
      pending: _pending(),
      result: _result,
    );
  }

  List<PendingQuestion> _pending() {
    if (_result != null) return const [];
    final inn = _current;
    if (inn.end != null) return const [];
    final questions = <PendingQuestion>[];
    final candidates = _batterCandidates(inn);
    if (!inn.openersSet) {
      questions.add(
        ChooseOpeners(
          battingTeamId: inn.battingTeamId,
          candidates: candidates,
          suggestedStriker: candidates[0],
          suggestedNonStriker: candidates[1],
        ),
      );
    } else if (inn.hasVacancy) {
      questions.add(
        ChooseBatter(
          battingTeamId: inn.battingTeamId,
          candidates: candidates,
          suggested: candidates.first,
          atStrikersEnd: inn.striker == null,
        ),
      );
    }
    if (inn.bowler == null) questions.add(bowlerOptions(midOver: false));
    return questions;
  }

  InningsState _snapshotInnings(_Innings inn) {
    final closed = inn.end != null;
    return InningsState(
      number: inn.number,
      kind: inn.kind,
      battingTeamId: inn.battingTeamId,
      bowlingTeamId: inn.bowlingTeamId,
      ballsPerOver: rules.ballsPerOver,
      runs: inn.runs,
      wickets: inn.wickets,
      legalBalls: inn.legalBalls,
      ballLimit: inn.ballLimit,
      maxWickets: inn.maxWickets,
      bowlerMaxBalls: _bowlerMaxBalls(inn),
      target: inn.target,
      extras: Extras(
        wides: inn.wides,
        noBalls: inn.noBalls,
        byes: inn.byes,
        legByes: inn.legByes,
      ),
      batters: [
        for (final b in inn.batters.values)
          BatterCard(
            playerId: b.id,
            position: b.position,
            runs: b.runs,
            balls: b.balls,
            fours: b.fours,
            sixes: b.sixes,
            status: closed && b.status == BatterStatus.batting
                ? BatterStatus.notOut
                : b.status,
            dismissal: b.dismissal,
          ),
      ],
      bowlers: [
        for (final b in inn.bowlers.values)
          if (b.legalBalls > 0 || b.wides > 0 || b.noBalls > 0)
            BowlerCard(
              playerId: b.id,
              legalBalls: b.legalBalls,
              maidens: b.maidens,
              runs: b.runs,
              wickets: b.wickets,
              wides: b.wides,
              noBalls: b.noBalls,
              dots: b.dots,
            ),
      ],
      fallOfWickets: List.unmodifiable(inn.fallOfWickets),
      partnerships: [
        for (final p in inn.partnerships)
          Partnership(
            batterIds: List.unmodifiable(p.ids),
            runs: p.runs,
            balls: p.balls,
          ),
      ],
      overs: [
        for (final o in inn.overs)
          if (o.deliveries.isNotEmpty || !closed)
            OverSummary(
              number: o.number,
              bowlerIds: List.unmodifiable(o.bowlers),
              deliveries: List.unmodifiable(o.deliveries),
              isComplete: o.complete || closed,
            ),
      ],
      strikerId: closed ? null : inn.striker,
      nonStrikerId: closed ? null : inn.nonStriker,
      bowlerId: inn.bowler,
      freeHitNext: !closed && inn.freeHitNext,
      endReason: inn.end,
    );
  }

  // ------------------------------------------------------------ text

  String _name(String playerId) {
    for (final team in [setup.teamA, setup.teamB]) {
      for (final p in team.players) {
        if (p.id == playerId) return p.name;
      }
    }
    return 'That player';
  }

  static String _ineligibilityText(BowlerIneligibility r) => switch (r) {
    BowlerIneligibility.bowledPreviousOver => 'they bowled the previous over',
    BowlerIneligibility.quotaReached => 'they have no overs left',
    BowlerIneligibility.currentBowler => 'they are already bowling',
    BowlerIneligibility.bowledPreviousSuperOver =>
      'they bowled in the previous super over',
  };

  static String _dismissalText(DismissalKind k) => switch (k) {
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
}

// ---------------------------------------------------------------- internals

final class _Batter {
  _Batter(this.id, this.position);

  final String id;
  final int position;
  int runs = 0;
  int balls = 0;
  int fours = 0;
  int sixes = 0;
  BatterStatus status = BatterStatus.batting;
  DismissalRecord? dismissal;

  /// Came back after retiring; not retired automatically again.
  bool returned = false;
}

final class _Bowler {
  _Bowler(this.id);

  final String id;
  int legalBalls = 0;
  int maidens = 0;
  int runs = 0;
  int wickets = 0;
  int wides = 0;
  int noBalls = 0;
  int dots = 0;
}

final class _Over {
  _Over(this.number);

  final int number;
  final List<String> bowlers = [];
  final List<DeliveryRecord> deliveries = [];
  int legalBalls = 0;
  int bowlerRuns = 0;
  bool complete = false;
}

final class _Partnership {
  _Partnership(this.ids);

  final List<String> ids;
  int runs = 0;
  int balls = 0;
}

final class _Innings {
  _Innings({
    required this.number,
    required this.kind,
    required this.battingTeamId,
    required this.bowlingTeamId,
    required this.ballLimit,
    required this.maxWickets,
    required this.target,
    required this.barredBatters,
    required this.barredBowlers,
  });

  final int number;
  final InningsKind kind;
  final String battingTeamId;
  final String bowlingTeamId;
  int? ballLimit;
  final int maxWickets;
  int? target;
  bool revisedTarget = false;
  final Set<String> barredBatters;
  final Set<String> barredBowlers;

  int runs = 0;
  int wickets = 0;
  int legalBalls = 0;
  int wides = 0;
  int noBalls = 0;
  int byes = 0;
  int legByes = 0;

  final Map<String, _Batter> batters = {};
  final Map<String, _Bowler> bowlers = {};
  final List<FallOfWicket> fallOfWickets = [];
  final List<_Partnership> partnerships = [];
  final List<_Over> overs = [];

  String? striker;
  String? nonStriker;
  String? bowler;
  bool openersSet = false;
  bool freeHitNext = false;

  /// The last batter is batting on their own.
  bool alone = false;
  InningsEndReason? end;

  _Over? get currentOver =>
      overs.isNotEmpty && !overs.last.complete ? overs.last : null;

  int get completedOvers => overs.where((o) => o.complete).length;

  bool get hasVacancy =>
      openersSet && (striker == null || (nonStriker == null && !alone));

  _Batter addBatter(String id) => batters[id] = _Batter(id, batters.length + 1);

  void swapEnds() {
    final s = striker;
    striker = nonStriker;
    nonStriker = s;
  }

  void vacate(String id) {
    if (striker == id) striker = null;
    if (nonStriker == id) nonStriker = null;
  }
}
