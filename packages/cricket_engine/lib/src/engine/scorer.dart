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
    for (final team in [setup.teamA, setup.teamB]) {
      _roster[team.id] = [for (final p in team.players) p.id];
    }
    _startInnings(
      kind: InningsKind.regular,
      battingTeamId: setup.battingFirstTeamId,
      ballLimit: rules.ballsPerInnings,
    );
  }

  final MatchSetup setup;
  final List<_Innings> _innings = [];
  MatchResult? _result;

  /// Who is playing for each side now, in batting order. Substitutions
  /// replace an id in place.
  final Map<String, List<String>> _roster = {};
  final Set<String> _replaced = {};
  final List<Substitute> _substitutions = [];

  /// Penalty runs waiting for a side that has not batted yet (Law 41.17).
  final Map<String, int> _carriedPenalty = {};
  bool _awaitingFollowOn = false;

  /// Follow-on margin adjusted for lost time, overriding the rules.
  int? _followOnMargin;

  /// Events applied so far; the log position of the event being applied.
  int _applied = 0;

  int _day = 1;
  final List<StoppageRecord> _stoppages = [];
  StoppageKind? _stoppedFor;

  MatchRules get rules => setup.rules;

  // ---------------------------------------------------------------- events

  void apply(MatchEvent event) {
    if (_result != null) {
      throw const IllegalEventException(
        IllegalEventCode.matchOver,
        'The match is over.',
      );
    }
    if (_awaitingFollowOn &&
        event is! FollowOn &&
        event is! Drawn &&
        event is! Abandoned &&
        event is! PenaltyRuns &&
        event is! Substitute &&
        event is! Stoppage) {
      throw const IllegalEventException(
        IllegalEventCode.followOnPending,
        'Decide whether to enforce the follow-on first.',
      );
    }
    switch (event) {
      case OpenersSelected():
        _openers(event);
      case BowlerSelected():
        _selectBowler(event.bowlerId, umpireAllowed: event.umpireAllowed);
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
      case Declare():
        _declare();
      case Forfeit():
        _forfeit();
      case FollowOn():
        _followOn(enforce: event.enforce);
      case Drawn():
        _requireTwoInnings(
          'A limited-overs match cannot be drawn; record it as abandoned '
          'instead.',
        );
        _endMatch(const Draw());
      case PenaltyRuns():
        _penalty(event);
      case Substitute():
        _substitute(event);
      case FollowOnMarginSet():
        _setFollowOnMargin(event.runs);
      case OverCalledEarly():
        _overCalledEarly();
      case OverExtended():
        _overExtended();
      case Abandoned():
        _endMatch(const NoResult());
      case Stoppage():
        _stoppage(event.kind);
      case Delivery():
        _delivery(event);
        _stoppedFor = null;
    }
    _applied++;
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

  void _selectBowler(String id, {bool umpireAllowed = false}) {
    final inn = _open;
    _requireOpeners(inn);
    if (!_roster[inn.bowlingTeamId]!.contains(id)) {
      throw IllegalEventException(
        IllegalEventCode.notInBowlingTeam,
        '${_name(id)} is not in the fielding side.',
      );
    }
    final current = inn.currentOver;
    final midOver = current != null && current.deliveries.isNotEmpty;
    final reason = _bowlerIneligibility(inn, id, midOver: midOver);
    // The umpire may let a bowler continue against the records, but the
    // bowler of the over cannot replace themselves.
    if (reason != null &&
        !(umpireAllowed && reason != BowlerIneligibility.currentBowler)) {
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
    // Both ends can be empty at once (a wicket and a retirement together);
    // the partnership starts when the second batter arrives.
    if (inn.striker != null && inn.nonStriker != null) {
      inn.partnerships.add(_Partnership([inn.striker!, inn.nonStriker!]));
    }
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

  void _requireTwoInnings(String message) {
    if (!rules.isTwoInnings) {
      throw IllegalEventException(IllegalEventCode.notAllowedInFormat, message);
    }
  }

  void _setFollowOnMargin(int runs) {
    _requireTwoInnings('The follow-on only applies to two-innings matches.');
    if (runs < 1) {
      throw const IllegalEventException(
        IllegalEventCode.notAllowedInFormat,
        'The follow-on margin must be at least 1 run.',
      );
    }
    if (_awaitingFollowOn ||
        _regularInnings.where((i) => i.end != null).length >= 2) {
      throw const IllegalEventException(
        IllegalEventCode.notAllowedInFormat,
        'The follow-on margin must be set before the second innings ends.',
      );
    }
    _followOnMargin = runs;
  }

  void _declare() {
    _requireTwoInnings('Declarations are only for two-innings matches.');
    final inn = _open;
    _requireOpeners(inn);
    _close(inn, InningsEndReason.declared);
  }

  void _forfeit() {
    _requireTwoInnings('Forfeits are only for two-innings matches.');
    final inn = _open;
    if (inn.openersSet) {
      throw const IllegalEventException(
        IllegalEventCode.notAllowedInFormat,
        'An innings can only be forfeited before it starts; declare instead.',
      );
    }
    _close(inn, InningsEndReason.forfeited);
  }

  void _followOn({required bool enforce}) {
    if (!_awaitingFollowOn) {
      throw const IllegalEventException(
        IllegalEventCode.notAllowedInFormat,
        'The follow-on is not available now.',
      );
    }
    _awaitingFollowOn = false;
    final regular = _regularInnings;
    _startInnings(
      kind: InningsKind.regular,
      battingTeamId: enforce
          ? regular[1].battingTeamId
          : regular[0].battingTeamId,
      ballLimit: rules.ballsPerInnings,
    );
  }

  void _stoppage(StoppageKind kind) {
    // At an innings break the score is the innings just finished.
    final inn = _current.openersSet || _innings.length == 1
        ? _current
        : _innings[_innings.length - 2];
    _stoppages.add(
      StoppageRecord(
        kind: kind,
        day: _day,
        inningsNumber: inn.number,
        battingTeamId: inn.battingTeamId,
        runs: inn.runs,
        wickets: inn.wickets,
        legalBalls: inn.legalBalls,
        inningsClosed: inn.end != null,
      ),
    );
    _stoppedFor = kind;
    if (kind == StoppageKind.stumps) _day++;
  }

  void _endMatch(MatchResult result) {
    final inn = _current;
    inn.end ??= InningsEndReason.closed;
    inn.bowler = null;
    _awaitingFollowOn = false;
    _result = result;
  }

  void _penalty(PenaltyRuns e) {
    if (e.runs < 1) {
      throw const IllegalEventException(
        IllegalEventCode.invalidPenalty,
        'Penalty runs must be at least 1.',
      );
    }
    if (e.teamId != setup.teamA.id && e.teamId != setup.teamB.id) {
      throw const IllegalEventException(
        IllegalEventCode.invalidPenalty,
        'Penalty runs go to one of the two sides.',
      );
    }
    final inn = _current;
    if (inn.end == null && inn.battingTeamId == e.teamId) {
      inn
        ..runs += e.runs
        ..penalty += e.runs;
      if (inn.partnerships.isNotEmpty) inn.partnerships.last.runs += e.runs;
      _afterChange(inn);
      return;
    }
    final completed = _regularInnings.lastWhereOrNull(
      (i) => i.battingTeamId == e.teamId && i.end != null,
    );
    if (completed != null) {
      completed
        ..runs += e.runs
        ..penalty += e.runs;
    } else {
      _carriedPenalty.update(
        e.teamId,
        (r) => r + e.runs,
        ifAbsent: () => e.runs,
      );
    }
    if (inn.end == null) _afterChange(inn);
  }

  void _substitute(Substitute e) {
    Never fail(String message) => throw IllegalEventException(
      IllegalEventCode.invalidSubstitution,
      message,
    );

    final teamId = _roster.entries
        .where((t) => t.value.contains(e.outPlayerId))
        .map((t) => t.key)
        .firstOrNull;
    if (teamId == null) fail('${_name(e.outPlayerId)} is not playing.');
    final team = setup.team(teamId);
    if (!team.substitutes.any((p) => p.id == e.inPlayerId)) {
      fail(
        '${_name(e.inPlayerId)} is not a named substitute for ${team.name}.',
      );
    }
    if (_roster[teamId]!.contains(e.inPlayerId) ||
        _replaced.contains(e.inPlayerId)) {
      fail('${_name(e.inPlayerId)} has already played in this match.');
    }
    final inn = _current;
    if (inn.end == null) {
      if (e.outPlayerId == inn.striker || e.outPlayerId == inn.nonStriker) {
        fail(
          '${_name(e.outPlayerId)} is batting; record them as retired first.',
        );
      }
      if (e.outPlayerId == inn.bowler) {
        fail(
          '${_name(e.outPlayerId)} is bowling; choose another bowler for '
          'the over first.',
        );
      }
    }
    final roster = _roster[teamId]!;
    roster[roster.indexOf(e.outPlayerId)] = e.inPlayerId;
    _replaced.add(e.outPlayerId);
    _substitutions.add(e);
  }

  void _revise(RevisedTarget e) {
    if (rules.ballsPerInnings == null) {
      throw const IllegalEventException(
        IllegalEventCode.notAllowedInFormat,
        'Revised targets are only for limited-overs matches.',
      );
    }
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
      if (_target(inn) == null) {
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
      inn.revisedTargetRuns = target;
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
        eventIndex: _applied,
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

    if (d.isLegal && over.legalBalls == rules.ballsPerOver + over.extraBalls) {
      _completeOver(inn, over);
    }

    _afterChange(inn);
  }

  void _completeOver(_Innings inn, _Over over) {
    over.complete = true;
    over.maidenTo = over.bowlers.length == 1 && over.bowlerRuns == 0
        ? over.bowlers.single
        : null;
    if (over.maidenTo != null) inn.bowlers[over.maidenTo]!.maidens++;
    inn.bowler = null;
    over.swappedEnds =
        !inn.alone && inn.completedOvers % rules.oversPerEnd == 0;
    if (over.swappedEnds) inn.swapEnds();
  }

  void _overCalledEarly() {
    final inn = _open;
    final over = inn.currentOver;
    if (over == null || over.legalBalls == 0) {
      throw const IllegalEventException(
        IllegalEventCode.notAllowedInFormat,
        'An over can only be called early after at least one legal ball.',
      );
    }
    final short = rules.ballsPerOver + over.extraBalls - over.legalBalls;
    over.extraBalls -= short;
    inn.ballAdjustment -= short;
    inn.bowlers[over.bowlers.last]!.ballAdjustment -= short;
    _completeOver(inn, over);
    _afterChange(inn);
  }

  void _overExtended() {
    final inn = _open;
    final over = inn.overs.isEmpty ? null : inn.overs.last;
    if (over == null || !over.complete || inn.bowler != null) {
      throw const IllegalEventException(
        IllegalEventCode.notAllowedInFormat,
        'An extra ball can only be added straight after the over ends.',
      );
    }
    if (over.swappedEnds) inn.swapEnds();
    if (over.maidenTo != null) inn.bowlers[over.maidenTo]!.maidens--;
    over
      ..complete = false
      ..maidenTo = null
      ..swappedEnds = false
      ..extraBalls += 1;
    inn.ballAdjustment += 1;
    inn.bowlers[over.bowlers.last]!.ballAdjustment += 1;
    inn.bowler = over.bowlers.last;
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
    final target = _target(inn);
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
    // Substitute fielders may take catches (Law 24.1), so the whole squad
    // counts.
    if (fielder != null &&
        !setup.team(inn.bowlingTeamId).squad.any((p) => p.id == fielder)) {
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
    if (!_roster[inn.battingTeamId]!.contains(id)) {
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
    } else if (_target(inn) case final t? when inn.runs >= t) {
      reason = InningsEndReason.targetReached;
    } else if (inn.ballLimit != null &&
        inn.legalBalls >= inn.ballLimit! + inn.ballAdjustment) {
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
    int? superOverTarget,
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
        fixedTarget: superOverTarget,
        barredBatters: barredBatters,
        barredBowlers: barredBowlers,
      ),
    );
    final carried = _carriedPenalty.remove(battingTeamId);
    if (carried != null) {
      _innings.last
        ..runs += carried
        ..penalty += carried;
    }
  }

  void _afterInningsClosed(_Innings inn) {
    if (_result != null) return;
    if (inn.kind == InningsKind.superOver) {
      _resolveSuperOver(inn);
      return;
    }
    final regular = _regularInnings;
    if (!rules.isTwoInnings) {
      if (regular.length == 1) {
        _startInnings(
          kind: InningsKind.regular,
          battingTeamId: inn.bowlingTeamId,
          ballLimit: inn.ballLimit,
        );
      } else {
        _resolveChase(inn);
      }
      return;
    }
    switch (regular.length) {
      case 1:
        _startInnings(
          kind: InningsKind.regular,
          battingTeamId: inn.bowlingTeamId,
          ballLimit: rules.ballsPerInnings,
        );
      case 2:
        final lead = regular[0].runs - regular[1].runs;
        final margin = _followOnMargin ?? rules.followOnMargin;
        if (margin != null && lead >= margin) {
          _awaitingFollowOn = true;
        } else {
          _startInnings(
            kind: InningsKind.regular,
            battingTeamId: regular[0].battingTeamId,
            ballLimit: rules.ballsPerInnings,
          );
        }
      case 3:
        // The side that has batted twice may still be behind (Law 16.1).
        final twice = inn.battingTeamId;
        final once = inn.bowlingTeamId;
        final behind = _totalFor(once) - _totalFor(twice);
        if (behind > 0) {
          _result = Win(winnerTeamId: once, margin: ByInningsAndRuns(behind));
        } else {
          _startInnings(
            kind: InningsKind.regular,
            battingTeamId: once,
            ballLimit: rules.ballsPerInnings,
          );
        }
      default:
        _resolveChase(inn);
    }
  }

  List<_Innings> get _regularInnings =>
      _innings.where((i) => i.kind == InningsKind.regular).toList();

  int _totalFor(String teamId) => _regularInnings
      .where((i) => i.battingTeamId == teamId)
      .fold(0, (sum, i) => sum + i.runs);

  /// Runs needed to win, for the last regular innings and super overs.
  int? _target(_Innings inn) {
    if (inn.revisedTargetRuns != null) return inn.revisedTargetRuns;
    if (inn.kind == InningsKind.superOver) return inn.fixedTarget;
    final regular = _regularInnings;
    if (regular.indexOf(inn) != rules.inningsPerSide * 2 - 1) return null;
    final own = regular
        .where((i) => i != inn && i.battingTeamId == inn.battingTeamId)
        .fold(0, (sum, i) => sum + i.runs);
    return _totalFor(inn.bowlingTeamId) - own + 1;
  }

  void _resolveChase(_Innings chase) {
    final target = _target(chase)!;
    if (chase.runs >= target) {
      _result = Win(
        winnerTeamId: chase.battingTeamId,
        margin: ByWickets(
          chase.maxWickets - chase.wickets,
          ballsRemaining: chase.ballLimit == null
              ? null
              : chase.ballLimit! + chase.ballAdjustment - chase.legalBalls,
        ),
        revisedTarget: chase.revisedTargetRuns != null,
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
        revisedTarget: chase.revisedTargetRuns != null,
      );
    }
  }

  void _resolveSuperOver(_Innings inn) {
    if (inn.fixedTarget == null) {
      _startInnings(
        kind: InningsKind.superOver,
        battingTeamId: inn.bowlingTeamId,
        ballLimit: rules.ballsPerOver,
        superOverTarget: inn.runs + 1,
        barredBatters: _previousSuperOver(inn.bowlingTeamId, batting: true),
        barredBowlers: _previousSuperOver(inn.battingTeamId, batting: false),
      );
      return;
    }
    final target = inn.fixedTarget!;
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
    final roster = _roster[inn.battingTeamId]!;
    final yetToBat = [
      for (final id in roster)
        if (!inn.batters.containsKey(id) && !inn.barredBatters.contains(id)) id,
    ];
    final retired = [
      for (final b in inn.batters.values)
        if (b.status == BatterStatus.retiredNotOut &&
            roster.contains(b.id) &&
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

  ({int balls, int extraOverBowlers})? _bowlerAllowance(_Innings inn) =>
      inn.kind == InningsKind.superOver
      ? null
      : rules.bowlerLimit.allowance(
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

    // Law 17.6, and 17.8 for a replacement mid-over: no more consecutive
    // overs than the format allows (one under the Laws).
    final completed = inn.overs.where((o) => o.complete).toList();
    var run = 0;
    for (final o in completed.reversed) {
      if (!o.bowlers.contains(id)) break;
      run++;
    }
    if (run >= rules.maxConsecutiveOversPerBowler) {
      return BowlerIneligibility.bowledPreviousOver;
    }

    final allowance = _bowlerAllowance(inn);
    if (allowance != null) {
      final over = inn.currentOver;
      var needed = midOver
          ? rules.ballsPerOver - over!.legalBalls
          : rules.ballsPerOver;
      if (inn.ballLimit != null) {
        needed = math.min(
          needed,
          inn.ballLimit! + inn.ballAdjustment - inn.legalBalls,
        );
      }
      // Quotas count overs, so balls from umpire miscounts do not use any.
      int used(_Bowler b) => b.legalBalls - b.ballAdjustment;
      final b = inn.bowlers[id];
      final total = (b == null ? 0 : used(b)) + needed;
      if (total > allowance.balls) {
        // Only a limited number of bowlers may bowl the extra over.
        final othersOver = inn.bowlers.values
            .where((o) => o.id != id && used(o) > allowance.balls)
            .length;
        if (total > allowance.balls + rules.ballsPerOver ||
            othersOver >= allowance.extraOverBowlers) {
          return BowlerIneligibility.quotaReached;
        }
      }
    }
    return null;
  }

  ChooseBowler bowlerOptions({required bool midOver}) {
    final inn = _current;
    final eligible = <String>[];
    final ineligible = <String, BowlerIneligibility>{};
    for (final id in _roster[inn.bowlingTeamId]!) {
      final reason = _bowlerIneligibility(inn, id, midOver: midOver);
      if (reason == null) {
        eligible.add(id);
      } else {
        ineligible[id] = reason;
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

  // ----------------------------------------------- cheap read access

  /// Lightweight view of the live position, for tools that replay large
  /// numbers of events and cannot afford a full [snapshot] each time.
  ({
    String? striker,
    String? nonStriker,
    String? bowler,
    bool openersSet,
    bool hasVacancy,
    bool inningsClosed,
    int inningsCount,
    int completedOvers,
    int currentOverDeliveries,
    bool awaitingFollowOn,
    bool matchOver,
  })
  get live {
    final inn = _current;
    return (
      striker: inn.striker,
      nonStriker: inn.nonStriker,
      bowler: inn.bowler,
      openersSet: inn.openersSet,
      hasVacancy: inn.hasVacancy,
      inningsClosed: inn.end != null,
      inningsCount: _innings.length,
      completedOvers: inn.completedOvers,
      currentOverDeliveries: inn.currentOver?.deliveries.length ?? 0,
      awaitingFollowOn: _awaitingFollowOn,
      matchOver: _result != null,
    );
  }

  int? get currentTarget => _target(_current);

  int? get currentBallLimit => _current.ballLimit;

  // -------------------------------------------------------- snapshots

  MatchState snapshot() {
    return MatchState(
      setup: setup,
      innings: [for (final inn in _innings) _snapshotInnings(inn)],
      pending: _pending(),
      result: _result,
      substitutions: List.unmodifiable(_substitutions),
      day: _day,
      stoppages: List.unmodifiable(_stoppages),
      stoppedFor: _result == null ? _stoppedFor : null,
    );
  }

  List<PendingQuestion> _pending() {
    if (_result != null) return const [];
    if (_awaitingFollowOn) {
      final regular = _regularInnings;
      return [
        ChooseFollowOn(
          leadingTeamId: regular[0].battingTeamId,
          trailingTeamId: regular[1].battingTeamId,
          lead: regular[0].runs - regular[1].runs,
        ),
      ];
    }
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
      ballLimit: inn.ballLimit == null
          ? null
          : inn.ballLimit! + inn.ballAdjustment,
      maxWickets: inn.maxWickets,
      bowlerMaxBalls: _bowlerMaxBalls(inn),
      target: _target(inn),
      extras: Extras(
        wides: inn.wides,
        noBalls: inn.noBalls,
        byes: inn.byes,
        legByes: inn.legByes,
        penalty: inn.penalty,
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
      for (final p in team.squad) {
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

  /// Extra (or, negative, missing) balls in overs the umpire miscounted.
  int ballAdjustment = 0;
}

final class _Over {
  _Over(this.number);

  final int number;
  final List<String> bowlers = [];
  final List<DeliveryRecord> deliveries = [];
  int legalBalls = 0;
  int bowlerRuns = 0;
  bool complete = false;

  /// Balls more (or, negative, fewer) than the standard over, when the
  /// umpire miscounted (Law 17.5).
  int extraBalls = 0;
  String? maidenTo;
  bool swappedEnds = false;
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
    required this.fixedTarget,
    required this.barredBatters,
    required this.barredBowlers,
  });

  final int number;
  final InningsKind kind;
  final String battingTeamId;
  final String bowlingTeamId;
  int? ballLimit;

  /// Change to the ball limit from miscounted overs.
  int ballAdjustment = 0;
  final int maxWickets;

  /// Super over target, set when the innings starts.
  final int? fixedTarget;

  /// Target given by the officials after an interruption.
  int? revisedTargetRuns;
  final Set<String> barredBatters;
  final Set<String> barredBowlers;

  int runs = 0;
  int wickets = 0;
  int legalBalls = 0;
  int wides = 0;
  int noBalls = 0;
  int byes = 0;
  int legByes = 0;
  int penalty = 0;

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

extension<T> on List<T> {
  T? lastWhereOrNull(bool Function(T) test) {
    for (var i = length - 1; i >= 0; i--) {
      if (test(this[i])) return this[i];
    }
    return null;
  }
}
