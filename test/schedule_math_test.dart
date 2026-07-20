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

  test('the past cannot be planned', () {
    final yesterday = tomorrow.subtract(const Duration(days: 2));
    tasks.addTasks([make('a', 60)]);
    tasks.autoScheduleDay(wake, sleep, alerts, 'Default', day: yesterday);

    expect(tasks.scheduleOn(yesterday), isEmpty);
    expect(tasks.canPlan(yesterday), isFalse);
    expect(tasks.canPlan(tomorrow), isTrue);
  });
}
