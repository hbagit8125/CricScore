# cricket_engine

The scoring engine behind CricScore. Pure Dart, no Flutter.

Every tap the scorer makes is a `MatchEvent`. The engine checks each event against the Laws of Cricket and the match's `MatchRules`, keeps it in an event log, and rebuilds the full match state from that log. Undo and edits replay the log, so the result is always exactly what scoring it that way would have given.

```dart
var match = Match.start(setup);                  // MatchSetup: rules, teams, toss
match.state.pending;                             // [ChooseOpeners, ChooseBowler]
match = match
    .apply(const OpenersSelected(strikerId: 'a1', nonStrikerId: 'a2'))
    .apply(const BowlerSelected('b11'))
    .apply(const Delivery.four())
    .apply(const Delivery.noBall(runs: 1));      // free hit next in T20
match.state.currentInnings!.runs;                // 6
match = match.undo();                            // back to 4
```

An event that breaks the rules throws `IllegalEventException` with a plain-language message and leaves the match unchanged.

## What the UI asks

`MatchState.pending` lists the only questions the scorer needs to answer before the next ball: openers, the next batter, or the next bowler. Each comes with the legal choices and a suggested answer, so the UI can pre-select it.

## Scope

Covered now (phase P1a): single-innings formats (T20, ODI, T10, The Hundred, custom); wides, no-balls, byes, leg byes, overthrows; all ten dismissals with the limits on wides, no-balls and free hits; strike changes; bowler quotas, consecutive overs and mid-over replacement; retirements; revised targets; ties, super overs and boundary count-back; last batter batting alone; junior retirement scores.

Coming in P1b: two-innings matches (follow-on, declarations, draws), penalty runs, substitutions, and replays of real published matches.

## Tests

```
dart test
```

Scenario tests cover each rule; `test/invariants_test.dart` plays randomised whole matches in every format and checks that totals, figures, quotas and over sequences always add up.
