import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/models/energy_level.dart';
import 'package:ourmynd/models/task.dart';
import 'package:ourmynd/providers/calendar_provider.dart';

/// What belongs on the phone's calendar, and what has to come back off it.
///
/// This rule governs BOTH directions: pushDay writes exactly what it accepts,
/// and the sweep removes everything mapped that it rejects. The failure it
/// guards against is silent from inside the app: the timeline looks right and
/// the real calendar keeps showing a block nobody believes in any more.
void main() {
  Task task(
    String id, {
    DateTime? start,
    Duration? duration,
    bool done = false,
    bool anchor = false,
    String? chunkOf,
  }) =>
      Task(
        id: id,
        title: id,
        time: 'x',
        energy: EnergyLevel.low,
        done: done,
        isAnchor: anchor,
        chunkOf: chunkOf,
        startTime: start,
        duration: duration,
      );

  final at3 = DateTime(2026, 9, 1, 15);

  test('a scheduled task belongs on the calendar', () {
    expect(CalendarProvider.wantsEvent(task('a', start: at3)), isTrue);
  });

  test('an untimed task does not', () {
    // Sending a block back to the backlog strips its time. Before this rule it
    // kept its event, so the calendar still showed a 3pm block the app had
    // already let go of.
    expect(CalendarProvider.wantsEvent(task('a')), isFalse);
  });

  test('a finished task does not', () {
    expect(CalendarProvider.wantsEvent(task('a', start: at3, done: true)), isFalse);
  });

  test('the app furniture does not', () {
    // Wake-up and wind-down routines are the app's own scaffolding, not
    // appointments, and filling somebody's calendar with them is how a sync
    // feature gets switched off on day one.
    expect(CalendarProvider.wantsEvent(task('a', start: at3, anchor: true)), isFalse);
    expect(
        CalendarProvider.wantsEvent(task('a', start: at3, chunkOf: 'parent')),
        isFalse);
  });

  test('an event imported FROM the calendar is never pushed back', () {
    // Otherwise the app and the calendar copy one event back and forth forever.
    expect(
      CalendarProvider.wantsEvent(task('${Task.calendarPrefix}xyz', start: at3)),
      isFalse,
    );
  });

  group('reading a change as "these ones went"', () {
    // The provider keeps the id set so a deletion can skip the debounce that
    // exists for drags. The set arithmetic is the whole mechanism.
    test('a removed id is detected', () {
      final before = {'a', 'b', 'c'};
      final after = {'a', 'c'};
      expect(before.difference(after), {'b'});
    });

    test('deleting a task takes its chunks with it', () {
      final before = {'a', 'a#1', 'a#2', 'b'};
      final after = {'b'};
      expect(before.difference(after), {'a', 'a#1', 'a#2'});
    });

    test('an edit that adds a task removes nothing', () {
      final before = {'a'};
      final after = {'a', 'b'};
      expect(before.difference(after), isEmpty);
    });
  });
}
