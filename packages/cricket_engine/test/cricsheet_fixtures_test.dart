import 'dart:convert';
import 'dart:io';

import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/cricsheet.dart';

/// Real matches from Cricsheet (see fixtures/cricsheet/README.md), replayed
/// ball by ball and compared with the published scorecards.
void main() {
  CricsheetReplay load(String id) {
    final file = File('test/fixtures/cricsheet/$id.json.gz');
    final json =
        jsonDecode(utf8.decode(gzip.decode(file.readAsBytesSync())))
            as Map<String, dynamic>;
    return replayCricsheet(id, json);
  }

  void expectReplay(
    String id,
    String description,
    void Function(MatchState state)? check,
  ) {
    test('$id: $description', () {
      final r = load(id);
      expect(r.skipped, isNull);
      expect(r.mismatches, isEmpty);
      // The event log alone rebuilds the same match.
      final rebuilt = Match.replay(r.setup!, r.events).state;
      expect(
        rebuilt.innings.map((i) => '${i.runs}/${i.wickets}'),
        r.state!.innings.map((i) => '${i.runs}/${i.wickets}'),
      );
      check?.call(r.state!);
    });
  }

  String result(MatchState s) => s.result!.describe(s.setup);

  expectReplay('1144530', '2019 World Cup final: tie, super over, count-back', (
    s,
  ) {
    expect(
      s.innings.where((i) => i.kind == InningsKind.superOver),
      hasLength(2),
    );
    expect(result(s), startsWith('England won on boundary count'));
  });

  expectReplay('1384429', 'ODI with a batter timed out', (s) {
    final timedOut = s.innings.first.batters.where(
      (b) => b.dismissal?.kind == DismissalKind.timedOut,
    );
    expect(timedOut, hasLength(1));
    expect(result(s), 'Bangladesh won by 3 wickets (53 balls left)');
  });

  expectReplay('1420222', 'ODI with penalty runs', (s) {
    expect(s.innings[1].extras.penalty, 5);
    expect((s.result! as Win).winnerTeamId, 'Nepal');
  });

  expectReplay('1059712', 'tied ODI without a super over', (s) {
    expect(s.result, isA<Tie>());
  });

  expectReplay('1127284', 'Test: follow-on after lost time, then a chase', (s) {
    expect(s.innings[1].battingTeamId, s.innings[2].battingTeamId);
    expect(result(s), 'Pakistan won by 5 wickets');
  });

  expectReplay('1022593', 'Test: follow-on and an innings win', (s) {
    expect(s.innings, hasLength(3));
    expect(result(s), 'India won by an innings and 92 runs');
  });

  expectReplay('1020041', 'Test: drawn', (s) {
    expect(s.result, isA<Draw>());
  });

  expectReplay('1000855', 'Test: declaration and a successful chase', (s) {
    expect(
      s.innings.where((i) => i.endReason == InningsEndReason.declared),
      isNotEmpty,
    );
    expect(result(s), 'Australia won by 7 wickets');
  });

  expectReplay('1417818', 'The Hundred: rain-affected', null);

  expectReplay('1417822', 'The Hundred: super over', (s) {
    expect(s.innings.last.ballsPerOver, 5);
    expect((s.result! as Win).winnerTeamId, 'Southern Brave');
  });

  expectReplay('1370351', 'IPL with impact players', (s) {
    expect(s.substitutions, hasLength(2));
    expect(
      s.substitutions.map((x) => x.reason),
      everyElement(SubstitutionReason.impactPlayer),
    );
    expect(result(s), 'Mumbai Indians won by 81 runs');
  });

  expectReplay('1136564', 'IPL with a seven-ball over', (s) {
    final longOvers = s.innings[1].overs.where(
      (o) => o.deliveries.where((d) => d.delivery.isLegal).length == 7,
    );
    expect(longOvers, hasLength(1));
    expect((s.result! as Win).winnerTeamId, 'Sunrisers Hyderabad');
  });

  expectReplay('1552859', 'five-over T20I: two overs per bowler', (s) {
    expect(s.innings[1].ballLimit, 30);
    expect(s.innings[1].bowlerMaxBalls, 12);
    expect(result(s), 'India won by 2 runs');
  });
}
