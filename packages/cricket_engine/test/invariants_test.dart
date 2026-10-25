import 'dart:math';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

/// Plays a whole match with random but plausible events. Events the engine
/// refuses are skipped, as a scorer's mistaken tap would be.
Match simulate(MatchRules rules, int seed) {
  final rng = Random(seed);
  T pick<T>(List<T> items) => items[rng.nextInt(items.length)];

  var m = Match.start(setupFor(rules, lionsBatFirst: rng.nextBool()));
  for (var step = 0; step < 6000 && !m.state.isComplete; step++) {
    final MatchEvent event;
    final pending = m.state.pending;
    if (pending.isNotEmpty) {
      event = switch (pending.first) {
        ChooseOpeners(:final candidates) => () {
          final shuffled = [...candidates]..shuffle(rng);
          return OpenersSelected(
            strikerId: shuffled[0],
            nonStrikerId: shuffled[1],
          );
        }(),
        ChooseBatter(:final candidates) => BatterIn(pick(candidates)),
        ChooseBowler(:final eligible) =>
          eligible.isEmpty
              ? const EndInnings()
              : BowlerSelected(pick(eligible)),
      };
    } else {
      event = _randomPlay(m, rng, pick);
    }
    try {
      m = m.apply(event);
    } on IllegalEventException {
      continue;
    }
  }
  return m;
}

MatchEvent _randomPlay(Match m, Random rng, T Function<T>(List<T>) pick) {
  final inn = m.inn;
  final roll = rng.nextDouble();
  if (roll < 0.004) return Retired(inn.strikerId!, out: rng.nextBool());
  if (roll < 0.006 && inn.nonStrikerId != null) {
    return RunOutBeforeDelivery(inn.nonStrikerId!);
  }
  if (roll < 0.008 && m.events.length > 30 && inn.target != null) {
    return RevisedTarget(
      ballsPerInnings: max(inn.legalBalls, (inn.ballLimit ?? 300) - 6),
    );
  }

  final kindRoll = rng.nextDouble();
  final kind = kindRoll < 0.06
      ? DeliveryKind.wide
      : kindRoll < 0.12
      ? DeliveryKind.noBall
      : DeliveryKind.legal;
  final runsTo = kind == DeliveryKind.wide
      ? RunsTo.batter
      : pick([...List.filled(8, RunsTo.batter), RunsTo.byes, RunsTo.legByes]);
  var completed = pick([0, 0, 0, 0, 1, 1, 1, 2, 2, 3]);
  var boundary = 0;
  if (rng.nextDouble() < 0.12) {
    completed = 0;
    boundary =
        runsTo == RunsTo.batter && kind != DeliveryKind.wide && rng.nextBool()
        ? 6
        : 4;
  }

  Dismissal? dismissal;
  if (rng.nextDouble() < 0.06) {
    final kinds = m.allowedDismissals(kind).toList();
    final dk = pick(kinds);
    final batter = dk.strikerOnly || inn.nonStrikerId == null
        ? inn.strikerId!
        : pick([inn.strikerId!, inn.nonStrikerId!]);
    dismissal = Dismissal(kind: dk, batterId: batter, crossed: rng.nextBool());
    if (dk.endsDeliveryWithoutRuns) completed = 0;
    boundary = 0;
  }
  return Delivery(
    kind: kind,
    runsTo: runsTo,
    completedRuns: completed,
    boundary: boundary,
    dismissal: dismissal,
  );
}

void checkInvariants(Match m) {
  final rules = m.setup.rules;
  for (final inn in m.state.innings) {
    final where = 'innings ${inn.number}';
    final deliveries = inn.overs.expand((o) => o.deliveries).toList();

    expect(
      inn.runs,
      inn.batters.fold(0, (s, b) => s + b.runs) + inn.extras.total,
      reason: '$where: total = batters + extras',
    );
    expect(
      inn.bowlers.fold(0, (s, b) => s + b.runs),
      inn.runs - inn.extras.byes - inn.extras.legByes - inn.extras.penalty,
      reason: '$where: bowlers are charged everything but byes and leg byes',
    );
    expect(
      inn.bowlers.fold(0, (s, b) => s + b.legalBalls),
      inn.legalBalls,
      reason: '$where: legal balls match the bowling figures',
    );
    expect(
      inn.batters.fold(0, (s, b) => s + b.balls),
      deliveries.where((d) => d.delivery.kind != DeliveryKind.wide).length,
      reason: '$where: balls faced = legal balls + no-balls',
    );
    expect(
      deliveries.fold(0, (s, d) => s + d.totalRuns),
      inn.runs,
      reason: '$where: over-by-over runs add up',
    );
    expect(
      inn.partnerships.fold(0, (s, p) => s + p.runs),
      inn.runs,
      reason: '$where: partnerships add up',
    );
    expect(
      inn.wickets,
      inn.batters.where((b) => b.status == BatterStatus.out).length,
      reason: '$where: wickets = batters out',
    );
    expect(inn.fallOfWickets, hasLength(inn.wickets), reason: where);
    expect(inn.wickets, lessThanOrEqualTo(inn.maxWickets), reason: where);
    if (inn.ballLimit != null) {
      expect(inn.legalBalls, lessThanOrEqualTo(inn.ballLimit!), reason: where);
    }
    for (var i = 1; i < inn.fallOfWickets.length; i++) {
      expect(
        inn.fallOfWickets[i].runs,
        greaterThanOrEqualTo(inn.fallOfWickets[i - 1].runs),
        reason: '$where: fall of wickets never goes down',
      );
    }
    if (inn.bowlerMaxBalls != null) {
      for (final b in inn.bowlers) {
        expect(
          b.legalBalls,
          lessThanOrEqualTo(inn.bowlerMaxBalls!),
          reason: '$where: ${b.playerId} within quota',
        );
      }
    }
    final complete = inn.overs
        .where((o) => o.isComplete && o.deliveries.isNotEmpty)
        .toList();
    for (var i = 0; i < complete.length; i++) {
      final o = complete[i];
      final legal = o.deliveries.where((d) => d.delivery.isLegal).length;
      if (i < complete.length - 1 || !inn.isClosed) {
        expect(legal, rules.ballsPerOver, reason: '$where over ${o.number}');
      }
      if (rules.maxConsecutiveOversPerBowler == 1 && i > 0) {
        expect(
          o.bowlerIds.toSet().intersection(complete[i - 1].bowlerIds.toSet()),
          isEmpty,
          reason: '$where: no bowler bowls consecutive overs',
        );
      }
    }
    if (inn.strikerId != null) {
      expect(inn.strikerId, isNot(inn.nonStrikerId), reason: where);
    }
  }
}

void main() {
  final variants = <MatchRules>[
    MatchRules.t20,
    MatchRules.t10,
    MatchRules.hundred,
    MatchRules.custom(overs: 6, playersPerSide: 6),
    MatchRules.custom(overs: 5, playersPerSide: 5).copyWith(
      lastBatterCanBatAlone: true,
      tieBreak: TieBreak.superOverThenBoundaryCount,
    ),
    MatchRules.custom(overs: 8, playersPerSide: 8).copyWith(
      retireAtRuns: 15,
      wideRuns: 2,
      noBallRuns: 2,
      freeHitAfterNoBall: true,
    ),
  ];

  for (final rules in variants) {
    for (var seed = 0; seed < 8; seed++) {
      test('${rules.name} ${rules.playersPerSide}-a-side, seed $seed', () {
        final m = simulate(rules, seed);
        expect(m.state.isComplete, isTrue, reason: 'match should finish');
        checkInvariants(m);

        // Replaying the log gives the same match.
        final replayed = Match.replay(m.setup, m.events);
        expect(
          replayed.state.innings.map((i) => '${i.runs}/${i.wickets}'),
          m.state.innings.map((i) => '${i.runs}/${i.wickets}'),
        );
        expect(
          replayed.state.result!.describe(m.setup),
          m.state.result!.describe(m.setup),
        );

        // Undoing the last event and redoing it is exact.
        final redo = m.undo().apply(m.events.last);
        expect(
          redo.state.result!.describe(m.setup),
          m.state.result!.describe(m.setup),
        );
      });
    }
  }

  test('one ODI checked after every event', () {
    final full = simulate(MatchRules.odi, 99);
    var m = Match.start(full.setup);
    for (final e in full.events) {
      m = m.apply(e);
      checkInvariants(m);
    }
    expect(m.state.isComplete, isTrue);
  });
}
