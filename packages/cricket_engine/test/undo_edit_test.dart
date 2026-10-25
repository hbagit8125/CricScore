import 'package:cricket_engine/cricket_engine.dart';
import 'package:test/test.dart';

import 'support/fixture.dart';

void main() {
  late Match m;
  setUp(() => m = started(MatchRules.t20));

  test('undo removes the last event exactly', () {
    final before = m.apply(const Delivery.four());
    final after = before.apply(const Delivery.six());
    final undone = after.undo();
    expect(undone.events, before.events);
    expect(undone.inn.runs, 4);
    expect(undone.inn.batter('A1')!.sixes, 0);
  });

  test('undo across an over boundary brings the bowler back', () {
    m = m.bowl(6);
    expect(m.inn.bowlerId, isNull);
    m = m.undo();
    expect(m.inn.bowlerId, 'B11');
    expect(m.inn.legalBalls, 5);
  });

  test('undo of a wicket restores the batter', () {
    m = m.apply(
      const Delivery.wicket(
        Dismissal(kind: DismissalKind.bowled, batterId: 'A1'),
      ),
    );
    m = m.undo();
    expect(m.inn.wickets, 0);
    expect(m.inn.strikerId, 'A1');
    expect(m.state.pending, isEmpty);
  });

  test('undo on an empty match does nothing', () {
    final fresh = Match.start(setupFor(MatchRules.t20));
    expect(fresh.canUndo, isFalse);
    expect(fresh.undo(), same(fresh));
  });

  test('editing an earlier ball recalculates everything after it', () {
    m = m.play(const [Delivery.runs(1), Delivery.four(), Delivery.dot()]);
    expect(m.inn.batter('A2')!.runs, 4);
    // The first ball was really a two: A1 keeps strike and gets the four.
    final edited = m.replaceAt(2, const Delivery.runs(2));
    expect(edited.inn.runs, 6);
    expect(edited.inn.batter('A1')!.runs, 6);
    expect(edited.inn.batter('A2')!.runs, 0);
  });

  test(
    'an edit that makes a later event illegal is refused with its index',
    () {
      m = m.play(const [
        Delivery.dot(),
        Delivery.wicket(Dismissal(kind: DismissalKind.bowled, batterId: 'A1')),
      ]);
      // A single first would put A2 on strike, so A1 could not be bowled.
      expect(
        () => m.replaceAt(2, const Delivery.runs(1)),
        throwsA(
          isA<IllegalEventException>()
              .having((e) => e.eventIndex, 'eventIndex', 3)
              .having((e) => e.code, 'code', IllegalEventCode.wrongBatterOut),
        ),
      );
    },
  );

  test('inserting and removing events', () {
    m = m.play(const [Delivery.dot(), Delivery.dot()]);
    final inserted = m.insertAt(3, const Delivery.wide());
    expect(inserted.inn.extras.wides, 1);
    expect(inserted.removeAt(3).events, m.events);
  });

  test('a refused event leaves the match unchanged', () {
    expect(
      () => m.apply(const BatterIn('A3')),
      throwsA(isA<IllegalEventException>()),
    );
    expect(m.events, hasLength(2));
  });
}
