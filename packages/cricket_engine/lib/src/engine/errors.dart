enum IllegalEventCode {
  invalidSetup,
  matchOver,
  inningsClosed,
  openersNeeded,
  openersAlreadyChosen,
  batterNeeded,
  bowlerNeeded,
  notInBattingTeam,
  notInBowlingTeam,
  samePlayer,
  batterUnavailable,
  noVacancy,
  notAtCrease,
  bowlerIneligible,
  invalidDelivery,
  dismissalNotAllowed,
  wrongBatterOut,
  invalidRevision,
  cannotSwapStrike,
  notAllowedInFormat,
  followOnPending,
  invalidPenalty,
  invalidSubstitution,
}

/// The engine refused an event because it breaks the Laws or the match's
/// rules. Nothing is recorded when this is thrown.
final class IllegalEventException implements Exception {
  const IllegalEventException(this.code, this.message, {this.eventIndex});

  final IllegalEventCode code;

  /// Plain-language reason, suitable to show the scorer.
  final String message;

  /// Position in the event log, when replaying an edited log.
  final int? eventIndex;

  IllegalEventException atIndex(int index) =>
      IllegalEventException(code, message, eventIndex: index);

  @override
  String toString() =>
      'IllegalEventException(${code.name}${eventIndex == null ? '' : ' at $eventIndex'}): $message';
}
