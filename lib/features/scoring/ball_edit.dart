import 'package:cricket_engine/cricket_engine.dart';

enum BallEditKind { change, insertBefore, remove }

/// A correction to one recorded ball.
final class BallEdit {
  const BallEdit.change(Delivery this.delivery) : kind = BallEditKind.change;

  const BallEdit.insertBefore(Delivery this.delivery)
    : kind = BallEditKind.insertBefore;

  const BallEdit.remove() : kind = BallEditKind.remove, delivery = null;

  final BallEditKind kind;
  final Delivery? delivery;
}

/// The event log after [edit] is made to [ball], and a note for the scorer
/// when the correction changed the length of an over.
///
/// Overs keep the balls they were scored with: a completed over that
/// loses a legal ball is recorded as called early by the umpire, and one
/// that gains a ball as extended (Law 17.5), so later overs keep their
/// bowlers. Removing a wicket also removes the batter who came in after it.
({List<MatchEvent> events, String? note}) correctedLog(
  Match match,
  DeliveryRecord ball,
  BallEdit edit,
) {
  final over = _overOf(match, ball);
  final events = [...match.events];
  final i = ball.eventIndex;
  final old = ball.delivery;
  int legal(Delivery? d) => d != null && d.isLegal ? 1 : 0;

  final original = [for (final d in over.deliveries) d.eventIndex];
  late List<int> positions;
  late int delta;
  var removesWicket = false;
  switch (edit.kind) {
    case BallEditKind.change:
      events[i] = edit.delivery!;
      delta = legal(edit.delivery) - legal(old);
      positions = original;
      removesWicket = old.dismissal != null && edit.delivery!.dismissal == null;
    case BallEditKind.insertBefore:
      events.insert(i, edit.delivery!);
      delta = legal(edit.delivery);
      positions = [for (final p in original) p >= i ? p + 1 : p, i]..sort();
    case BallEditKind.remove:
      events.removeAt(i);
      delta = -legal(old);
      positions = [
        for (final p in original)
          if (p != i) p > i ? p - 1 : p,
      ];
      removesWicket = old.dismissal != null;
  }

  if (removesWicket) {
    final from = edit.kind == BallEditKind.remove ? i : i + 1;
    for (var k = from; k < events.length && events[k] is! Delivery; k++) {
      if (events[k] is BatterIn) {
        events.removeAt(k);
        positions = [for (final p in positions) p > k ? p - 1 : p];
        break;
      }
    }
  }

  if (!over.isComplete || delta == 0 || positions.isEmpty) {
    return (events: events, note: null);
  }
  final legalBefore = over.deliveries.where((d) => d.delivery.isLegal).length;
  if (delta < 0) {
    events.insert(positions.last + 1, const OverCalledEarly());
    return (
      events: events,
      note: 'Over ${over.number} now has ${legalBefore - 1} balls, as called.',
    );
  }
  // The ball that ended the over before the correction ends it again, and
  // the umpire allowed one more.
  var count = 0;
  for (final p in positions) {
    if (events[p] case Delivery(isLegal: true)) count++;
    if (count == legalBefore) {
      events.insert(p + 1, const OverExtended());
      break;
    }
  }
  return (
    events: events,
    note: 'Over ${over.number} now has ${legalBefore + 1} balls.',
  );
}

OverSummary _overOf(Match match, DeliveryRecord ball) {
  for (final inn in match.state.innings) {
    for (final over in inn.overs) {
      if (over.deliveries.any((d) => d.eventIndex == ball.eventIndex)) {
        return over;
      }
    }
  }
  throw ArgumentError('That ball is not in this match.');
}
