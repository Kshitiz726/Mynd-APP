import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/models/energy_level.dart';
import 'package:ourmynd/models/task.dart';
import 'package:ourmynd/providers/alerts_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// The schedule is the product's spine, so its arithmetic is pinned here:
/// anchors never move, blocks never overlap, and nothing escapes the day.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TaskProvider tasks;
  late AlertsProvider alerts;
  late DateTime tomorrow;

  const wake = TimeOfDay(hour: 8, minute: 0);
  const sleep = TimeOfDay(hour: 22, minute: 0);

  setUp(() {
    // The scheduler pokes the alarm service, which owns an AudioPlayer; there is
    // no platform side in a unit test, so the channels are stubbed to no-ops.
    for (final name in ['xyz.luan/audioplayers', 'xyz.luan/audioplayers.global']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(const EventChannel('xyz.luan/audioplayers.global/events'), null);

    tasks = TaskProvider();
    alerts = AlertsProvider();
    final now = DateTime.now();
    // A future day keeps the maths independent of the clock at test time.
    tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
  });

  Task make(String id, int minutes) => Task(
        id: id,
        title: id,
        time: 'today',
        energy: EnergyLevel.high,
        duration: Duration(minutes: minutes),
      );

  test('auto-schedule pins wake and wind-down to the settings times', () {
    tasks.addTasks([make('a', 60), make('b', 30)]);
    tasks.autoScheduleDay(wake, sleep, alerts, 'Default', day: tomorrow);

    final day = tasks.scheduleOn(tomorrow);
    final wakeBlock = day.firstWhere((t) => t.id == 'wake_anchor');
    final sleepBlock = day.firstWhere((t) => t.id == 'sleep_anchor');

    expect(wakeBlock.startTime, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8, 0));
    // Wind-down starts half an hour before bedtime.
    expect(sleepBlock.startTime, DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21, 30));
  });

  test('no two blocks on the day overlap', () {
    tasks.addTasks([make('a', 60), make('b', 45), make('c', 30)]);
    tasks.autoScheduleDay(wake, sleep, alerts, 'Default', day: tomorrow);

    final day = tasks.scheduleOn(tomorrow);
    for (var i = 0; i < day.length - 1; i++) {
      expect(
        day[i].endTime!.isAfter(day[i + 1].startTime!),
        isFalse,
        reason: '${day[i].title} ends after ${day[i + 1].title} starts',
      );
    }
  });

  test('everything scheduled falls inside the waking day', () {
    tasks.addTasks([make('a', 60), make('b', 45)]);
    tasks.autoScheduleDay(wake, sleep, alerts, 'Default', day: tomorrow);

    final dayStart = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 8, 0);
    final dayEnd = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 22, 0);
    for (final t in tasks.scheduleOn(tomorrow)) {
      expect(t.startTime!.isBefore(dayStart), isFalse, reason: '${t.title} starts before waking');
      expect(t.endTime!.isAfter(dayEnd), isFalse, reason: '${t.title} runs past bedtime');
    }
  });

  test('reordering moves blocks but never the anchors', () {
    tasks.addTasks([make('a', 60), make('b', 30)]);
    tasks.autoScheduleDay(wake, sleep, alerts, 'Default', day: tomorrow);

    final before = tasks.scheduleOn(tomorrow);
    final wakeBlock = before.firstWhere((t) => t.id == 'wake_anchor');
    final sleepBlock = before.firstWhere((t) => t.id == 'sleep_anchor');
    final wakeAt = wakeBlock.startTime!;
    final sleepAt = sleepBlock.startTime!;

    final movable = before.where((t) => !t.isAnchor).toList().reversed.toList();
    tasks.recalculateSchedule(movable, wakeBlock.endTime!, sleepAt, 'Default');

    expect(wakeBlock.startTime, wakeAt, reason: 'wake anchor moved');
    expect(sleepBlock.startTime, sleepAt, reason: 'sleep anchor moved');

    // The reordered blocks are laid back-to-back from the end of the wake block.
    var cursor = wakeBlock.endTime!;
    for (final t in movable) {
      expect(t.startTime, cursor);
      cursor = cursor.add(t.duration!);
    }
  });

  test('a block that no longer fits before bedtime returns to the backlog', () {
    tasks.addTasks([make('big', 600)]); // 10 hours
    tasks.autoScheduleDay(wake, sleep, alerts, 'Default', day: tomorrow);

    final movable = tasks.scheduleOn(tomorrow).where((t) => !t.isAnchor).toList();
    final windowStart = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21, 0);
    final windowEnd = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 21, 30);
    tasks.recalculateSchedule(movable, windowStart, windowEnd, 'Default');

    for (final t in movable) {
      expect(t.scheduled, isFalse, reason: '${t.title} was left overflowing the day');
    }
  });

  // ── The ripple: moving a block re-flows the day instead of being refused ──

  /// Three touching hour-long blocks, 9:00, 10:00, 11:00, on a free day.
  ({Task a, Task b, Task cc, DateTime dayStart, DateTime dayEnd}) threeInARow() {
    final a = make('a', 60), b = make('b', 60), cc = make('c', 60);
    tasks.addTasks([a, b, cc]);
    final at = (int h) => DateTime(tomorrow.year, tomorrow.month, tomorrow.day, h, 0);
    tasks.setTaskTime(a, at(9), at(10));
    tasks.setTaskTime(b, at(10), at(11));
    tasks.setTaskTime(cc, at(11), at(12));
    return (a: a, b: b, cc: cc, dayStart: at(8), dayEnd: at(22));
  }

  test('stretching a block pushes the ones after it, and cascades', () {
    final d = threeInARow();
    final at = (int h) => DateTime(tomorrow.year, tomorrow.month, tomorrow.day, h, 0);

    // A was 9-10; make it 9-11, the case from the report.
    final overrun = tasks.rippleTaskTime(d.a, at(9), at(11), d.dayStart, d.dayEnd);

    expect(overrun, Duration.zero);
    expect(d.a.endTime, at(11));
    expect(d.b.startTime, at(11), reason: 'B did not give way');
    expect(d.b.endTime, at(12));
    expect(d.cc.startTime, at(12), reason: 'the push did not cascade to C');
    // Durations are preserved: the day moves, it does not compress.
    expect(d.b.duration, const Duration(minutes: 60));
    expect(d.cc.duration, const Duration(minutes: 60));
  });

  test('dragging a block earlier pulls its predecessor back', () {
    final d = threeInARow();
    final at = (int h, [int m = 0]) =>
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, h, m);

    // B moves from 10:00 up to 9:30, straight into A.
    tasks.rippleTaskTime(d.b, at(9, 30), at(10, 30), d.dayStart, d.dayEnd);

    expect(d.b.startTime, at(9, 30));
    expect(d.a.endTime, at(9, 30), reason: 'A was not pulled back off B');
    expect(d.a.startTime, at(8, 30));
    expect(d.a.duration, const Duration(minutes: 60), reason: 'A was squashed');
    expect(d.cc.startTime, at(10, 30), reason: 'C did not follow B');
  });

  test('no two blocks overlap after any ripple', () {
    final d = threeInARow();
    final at = (int h, [int m = 0]) =>
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, h, m);

    tasks.rippleTaskTime(d.cc, at(9, 15), at(10, 45), d.dayStart, d.dayEnd);

    final day = tasks.scheduleOn(tomorrow).where((t) => !t.isAnchor).toList();
    expect(day.length, 3, reason: 'a block fell off the day');
    for (var i = 0; i < day.length - 1; i++) {
      expect(day[i].endTime!.isAfter(day[i + 1].startTime!), isFalse,
          reason: '${day[i].title} overlaps ${day[i + 1].title}');
    }
  });

  test('a predecessor with nowhere to go is re-queued, never dropped', () {
    final d = threeInARow();
    final at = (int h, [int m = 0]) =>
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, h, m);

    // B lands at 8:00 - the very start of the day - so A cannot fit before it.
    tasks.rippleTaskTime(d.b, at(8), at(9), d.dayStart, d.dayEnd);

    expect(d.b.startTime, at(8));
    expect(d.a.scheduled, isTrue, reason: 'A was dropped from the day');
    expect(d.a.startTime!.isBefore(at(9)), isFalse, reason: 'A still overlaps B');
    expect(d.a.duration, const Duration(minutes: 60));
  });

  test('pushing the day past wind-down is reported, not silently allowed', () {
    final d = threeInARow();
    final at = (int h, [int m = 0]) =>
        DateTime(tomorrow.year, tomorrow.month, tomorrow.day, h, m);

    // Stretching A by an hour runs the chain to 13:00. Against a day that ends
    // at 12:30 that is exactly half an hour of overflow - and it is reported
    // rather than refused.
    final overrun = tasks.rippleTaskTime(d.a, at(9), at(11), d.dayStart, at(12, 30));

    expect(overrun, const Duration(minutes: 30));
  });

  test('inserting your own block slots it in and pushes the rest down', () {
    final d = threeInARow();
    final at = (int h) => DateTime(tomorrow.year, tomorrow.month, tomorrow.day, h, 0);
    final mine = make('mine', 30);

    tasks.insertTaskAt(mine, at(10), const Duration(minutes: 30), d.dayStart, d.dayEnd);

    expect(mine.startTime, at(10));
    expect(mine.scheduled, isTrue);
    expect(tasks.scheduleOn(tomorrow).map((t) => t.id), contains('mine'));
    expect(d.a.startTime, at(9), reason: 'the block before the insert moved');
    expect(d.b.startTime, at(10).add(const Duration(minutes: 30)));
    expect(d.cc.startTime, at(11).add(const Duration(minutes: 30)));
  });

  test('the past cannot be planned', () {
    final yesterday = tomorrow.subtract(const Duration(days: 2));
    tasks.addTasks([make('a', 60)]);
    tasks.autoScheduleDay(wake, sleep, alerts, 'Default', day: yesterday);

    expect(tasks.scheduleOn(yesterday), isEmpty);
    expect(tasks.canPlan(yesterday), isFalse);
    expect(tasks.canPlan(tomorrow), isTrue);
  });
}
