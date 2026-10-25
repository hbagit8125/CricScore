import '../model/events.dart';
import '../model/match_setup.dart';
import '../state/match_state.dart';
import '../state/pending.dart';
import 'errors.dart';
import 'scorer.dart';

/// An immutable match: its setup, the event log, and the state rebuilt from
/// that log.
///
/// Every change returns a new [Match]. Because state is always rebuilt from
/// the log, undo and edits give exactly the result of scoring it that way in
/// the first place.
final class Match {
  Match._(this.setup, List<MatchEvent> events, this._scorer)
    : events = List.unmodifiable(events),
      state = _scorer.snapshot();

  /// A new match with no events yet. Throws [IllegalEventException] with
  /// [IllegalEventCode.invalidSetup] when the setup is not usable.
  factory Match.start(MatchSetup setup) => Match.replay(setup, const []);

  /// Rebuilds a match from a saved or edited event log.
  ///
  /// Throws [IllegalEventException] carrying the index of the first event
  /// that is not valid at its point in the log.
  factory Match.replay(MatchSetup setup, List<MatchEvent> events) {
    final problems = setup.validate();
    if (problems.isNotEmpty) {
      throw IllegalEventException(
        IllegalEventCode.invalidSetup,
        problems.join(' '),
      );
    }
    final scorer = Scorer(setup);
    for (var i = 0; i < events.length; i++) {
      try {
        scorer.apply(events[i]);
      } on IllegalEventException catch (e) {
        throw e.atIndex(i);
      }
    }
    return Match._(setup, events, scorer);
  }

  final MatchSetup setup;
  final List<MatchEvent> events;
  final MatchState state;
  final Scorer _scorer;

  /// Records [event]. Throws [IllegalEventException] and leaves this match
  /// unchanged when the event breaks the Laws or the match's rules.
  Match apply(MatchEvent event) {
    final scorer = Scorer(setup);
    for (final e in events) {
      scorer.apply(e);
    }
    scorer.apply(event);
    return Match._(setup, [...events, event], scorer);
  }

  bool get canUndo => events.isNotEmpty;

  /// Removes the last event.
  Match undo() => canUndo
      ? Match.replay(setup, events.sublist(0, events.length - 1))
      : this;

  /// Replaces the event at [index] and replays the rest of the log.
  Match replaceAt(int index, MatchEvent event) =>
      Match.replay(setup, [...events]..[index] = event);

  /// Removes the event at [index] and replays the rest of the log.
  Match removeAt(int index) =>
      Match.replay(setup, [...events]..removeAt(index));

  /// Inserts [event] before [index] and replays the rest of the log.
  Match insertAt(int index, MatchEvent event) =>
      Match.replay(setup, [...events]..insert(index, event));

  /// Who may bowl now. With [midOver] true, who may finish the current over
  /// after the bowler cannot continue (Law 17.8).
  ChooseBowler bowlerOptions({bool midOver = false}) =>
      _scorer.bowlerOptions(midOver: midOver);

  /// Dismissals the scorer can record on the next delivery of [kind],
  /// taking a free hit into account.
  Set<DismissalKind> allowedDismissals(DeliveryKind kind) =>
      _scorer.allowedDismissals(kind);
}
