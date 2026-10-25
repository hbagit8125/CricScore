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

  bool get isComplete => result != null;

  InningsState? get currentInnings => innings.isEmpty ? null : innings.last;

  /// True when the next event can be a delivery.
  bool get readyForDelivery =>
      !isComplete &&
      pending.isEmpty &&
      currentInnings != null &&
      !currentInnings!.isClosed;
}
