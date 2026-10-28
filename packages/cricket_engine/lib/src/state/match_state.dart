import '../model/events.dart';
import '../model/match_setup.dart';
import 'innings_state.dart';
import 'pending.dart';
import 'result.dart';

/// A read-only view of the whole match, rebuilt from the event log.
final class MatchState {
  const MatchState({
    required this.setup,
    required this.innings,
    required this.pending,
    required this.result,
    this.substitutions = const [],
    this.day = 1,
    this.stoppages = const [],
    this.stoppedFor,
  });

  final MatchSetup setup;

  /// Every innings so far, super overs included, in order.
  final List<InningsState> innings;

  /// Questions to answer before the next delivery, in the order to ask
  /// them. Empty when play can continue or the match is over.
  final List<PendingQuestion> pending;
  final MatchResult? result;

  /// Substitutions made so far, in order.
  final List<Substitute> substitutions;

  /// Day of play, starting at 1; each stumps starts the next.
  final int day;

  /// Every stoppage so far, in order.
  final List<StoppageRecord> stoppages;

  /// Why play is stopped now, or null while play is on. Cleared by the
  /// next ball.
  final StoppageKind? stoppedFor;

  /// Close-of-play scores, one per day completed.
  Iterable<StoppageRecord> get closeOfPlay =>
      stoppages.where((s) => s.kind == StoppageKind.stumps);

  bool get isComplete => result != null;

  InningsState? get currentInnings => innings.isEmpty ? null : innings.last;

  /// True when the next event can be a delivery.
  bool get readyForDelivery =>
      !isComplete &&
      pending.isEmpty &&
      currentInnings != null &&
      !currentInnings!.isClosed;
}

/// A stoppage and the score when it happened.
final class StoppageRecord {
  const StoppageRecord({
    required this.kind,
    required this.day,
    required this.inningsNumber,
    required this.battingTeamId,
    required this.runs,
    required this.wickets,
    required this.legalBalls,
    required this.inningsClosed,
  });

  final StoppageKind kind;

  /// The day it happened on.
  final int day;

  /// [InningsState.number] of the latest innings at the time.
  final int inningsNumber;
  final String battingTeamId;
  final int runs;
  final int wickets;
  final int legalBalls;

  /// The stoppage came at the end of an innings, before the next started.
  final bool inningsClosed;
}
