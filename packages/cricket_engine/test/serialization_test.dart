import 'dart:convert';
import 'dart:io';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'invariants_test.dart' as sim;
import 'support/cricsheet.dart';
import 'support/fixture.dart';

/// Encodes to a JSON string and back, as storage does.
T roundTrip<T>(
  Map<String, Object?> json,
  T Function(Map<String, Object?>) read,
) => read((jsonDecode(jsonEncode(json)) as Map).cast<String, Object?>());

void main() {
  test('every event type survives a round trip', () {
    const events = <MatchEvent>[
      OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'),
      BowlerSelected('B11'),
      BowlerSelected('B10', umpireAllowed: true),
      BatterIn('A3'),
      SwapStrike(),
      Retired('A1', out: false),
      Retired('A1', out: true),
      TimedOut('A4'),
      RunOutBeforeDelivery('A2'),
      RevisedTarget(ballsPerInnings: 60),
      RevisedTarget(ballsPerInnings: 60, target: 101),
      RevisedTarget(target: 90),
      EndInnings(),
      Abandoned(),
      Declare(),
      Forfeit(),
      FollowOn(enforce: true),
      FollowOnMarginSet(150),
      Drawn(),
      PenaltyRuns(teamId: 'LIO', runs: 5),
      Substitute(
        outPlayerId: 'A5',
        inPlayerId: 'AS',
        reason: SubstitutionReason.concussion,
      ),
      OverCalledEarly(),
      OverExtended(),
      Delivery.dot(),
      Delivery.six(),
      Delivery(completedRuns: 1, boundary: 4),
      Delivery.wide(runs: 2),
      Delivery.wide(boundary: true),
      Delivery.noBall(runsTo: RunsTo.legByes, runs: 1),
      Delivery.byes(3),
      Delivery.wicket(
        Dismissal(kind: DismissalKind.caught, batterId: 'A1', fielderId: 'B3'),
      ),
      Delivery.wicket(
        Dismissal(
          kind: DismissalKind.runOut,
          batterId: 'A2',
          fielderId: 'B1',
          crossed: true,
        ),
        runs: 1,
      ),
      Delivery(
        kind: DeliveryKind.wide,
        dismissal: Dismissal(kind: DismissalKind.stumped, batterId: 'A1'),
      ),
    ];
    for (final e in [
      ...events,
      for (final kind in StoppageKind.values) Stoppage(kind),
    ]) {
      expect(roundTrip(MatchJson.eventToJson(e), MatchJson.eventFromJson), e);
    }
  });

  test('a plain dot ball is stored compactly', () {
    expect(MatchJson.eventToJson(const Delivery.dot()), {'type': 'delivery'});
  });

  test('setups of every preset survive a round trip', () {
    for (final rules in [
      ...MatchRules.presets,
      ...MatchRules.multiDayPresets,
      MatchRules.multiDay(days: 2, playersPerSide: 9),
      MatchRules.custom(overs: 6, playersPerSide: 6).copyWith(
        retireAtRuns: 20,
        lastBatterCanBatAlone: true,
        bowlerLimit: const FixedBowlerLimit(12),
        tieBreak: TieBreak.superOverThenBoundaryCount,
      ),
    ]) {
      final setup = setupFor(rules);
      final back = roundTrip(
        MatchJson.setupToJson(setup),
        MatchJson.setupFromJson,
      );
      expect(
        MatchJson.setupToJson(back),
        MatchJson.setupToJson(setup),
        reason: rules.name,
      );
      expect(back.teamA.substitutes, setup.teamA.substitutes);
    }
  });

  test('data from a newer app version is refused', () {
    final json = MatchJson.setupToJson(setupFor(MatchRules.t20))
      ..['v'] = engineSchemaVersion + 1;
    expect(() => MatchJson.setupFromJson(json), throwsFormatException);
  });

  test('unknown event types are refused', () {
    expect(
      () => MatchJson.eventFromJson({'type': 'teaBreak'}),
      throwsFormatException,
    );
  });

  test('whole matches rebuild identically from stored JSON', () {
    final matches = [
      for (final r in [MatchRules.t20, MatchRules.hundred, MatchRules.test])
        for (var seed = 0; seed < 3; seed++) sim.simulate(r, seed),
      for (final id in ['1144530', '1127284', '1370351', '1136564'])
        () {
          final file = File('test/fixtures/cricsheet/$id.json.gz');
          final json =
              jsonDecode(utf8.decode(gzip.decode(file.readAsBytesSync())))
                  as Map<String, dynamic>;
          final r = replayCricsheet(id, json);
          return Match.replay(r.setup!, r.events);
        }(),
    ];
    for (final m in matches) {
      final setup = roundTrip(
        MatchJson.setupToJson(m.setup),
        MatchJson.setupFromJson,
      );
      final events = [
        for (final e in m.events)
          roundTrip(MatchJson.eventToJson(e), MatchJson.eventFromJson),
      ];
      expect(events, m.events);
      final rebuilt = Match.replay(setup, events);
      expect(
        rebuilt.state.innings.map(
          (i) => '${i.runs}/${i.wickets}/${i.legalBalls}',
        ),
        m.state.innings.map((i) => '${i.runs}/${i.wickets}/${i.legalBalls}'),
      );
      expect(
        rebuilt.state.result?.describe(setup),
        m.state.result?.describe(m.setup),
      );
    }
  });
}
