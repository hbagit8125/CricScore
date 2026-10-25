import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

/// Lions (A1..An) bat first against Tigers (B1..Bn) unless stated.
MatchSetup setupFor(MatchRules rules, {bool lionsBatFirst = true}) {
  TeamSheet team(String id, String name, String prefix) => TeamSheet(
    id: id,
    name: name,
    players: [
      for (var i = 1; i <= rules.playersPerSide; i++)
        PlayerRef(id: '$prefix$i', name: '$prefix$i'),
    ],
    substitutes: [PlayerRef(id: '${prefix}S', name: '${prefix}S')],
  );
  return MatchSetup(
    rules: rules,
    teamA: team('LIO', 'Lions', 'A'),
    teamB: team('TIG', 'Tigers', 'B'),
    toss: Toss(
      wonByTeamId: 'LIO',
      decision: lionsBatFirst ? TossDecision.bat : TossDecision.bowl,
    ),
  );
}

/// A match with openers A1 (striker) and A2 in, and B11 (or the last
/// player) bowling.
Match started(MatchRules rules) {
  final last = rules.playersPerSide;
  return Match.start(setupFor(rules))
      .apply(const OpenersSelected(strikerId: 'A1', nonStrikerId: 'A2'))
      .apply(BowlerSelected('B$last'));
}

extension MatchTestHelpers on Match {
  InningsState get inn => state.currentInnings!;

  Match play(Iterable<MatchEvent> events) =>
      events.fold(this, (m, e) => m.apply(e));

  /// Bowls [count] copies of [delivery].
  Match bowl(int count, [Delivery delivery = const Delivery.dot()]) =>
      play(List.filled(count, delivery));

  /// Starts the next over with [bowlerId].
  Match over(String bowlerId) => apply(BowlerSelected(bowlerId));
}

/// Expects [action] to be refused with [code].
Matcher throwsIllegal(IllegalEventCode code) =>
    throwsA(isA<IllegalEventException>().having((e) => e.code, 'code', code));
