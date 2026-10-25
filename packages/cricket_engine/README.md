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

- **Formats:** T20, ODI, T10, The Hundred, Test, first-class and custom rules (team size, balls per over, wide and no-ball values, free hits, LBW, last batter alone, junior retirement score, tie-breaks).
- **Deliveries:** wides, no-balls, byes, leg byes and overthrows; strike follows runs actually run; overs the umpire miscounts stand (Law 17.5).
- **Dismissals:** all ten, limited correctly on wides, no-balls and free hits, including run outs at either end, run out before the ball is bowled, retirements and timed out.
- **Bowling:** no consecutive overs, quotas for full and shortened ODIs and T20s, mid-over replacement.
- **Innings and results:** all out, overs, targets, rain-revised targets, declarations, forfeits, follow-on (including a margin reduced for lost time), innings victories, draws, ties, repeated super overs, boundary count-back, abandonment.
- **Other:** penalty runs (Law 41) and substitutions (concussion, impact player).

## Tests

```
dart test
```

- Scenario tests cover each rule.
- `test/invariants_test.dart` plays randomised whole matches in every format and checks that totals, figures, quotas and over sequences always add up.
- `test/cricsheet_fixtures_test.dart` replays 13 real matches from [Cricsheet](https://cricsheet.org) and compares them with the published scorecards.
- `test/cricsheet_bulk_test.dart` does the same for a whole Cricsheet download (not run in CI). Across 8,551 men's Tests, ODIs, T20 internationals, IPL and Hundred matches, 8,526 match exactly; the rest are data errors, umpire slips the engine correctly refuses, or rain targets set part-way through a chase that the data cannot place.
