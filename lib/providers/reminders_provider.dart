import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/goal.dart';
import '../models/reminder.dart';
import '../models/task.dart';
import '../services/notification_service.dart';

/// The reminders the user set, and the promise that they will actually arrive.
///
/// Two things were wrong before. The list was hardcoded in the widget, so a
/// reminder you added was gone on the next build and a toggle you flipped meant
/// nothing. And nothing was ever handed to the OS, so even a real reminder
/// could only fire while the app was open and in front of you.
///
/// Every change here ends in [_sync], which hands the whole set to the system
/// scheduler. That is deliberately blunt: cancelling everything and re-adding
/// what should exist is cheap, and it cannot drift out of step with what the
/// screen is showing, which a clever diff eventually would.
class RemindersProvider extends ChangeNotifier {
  RemindersProvider() {
    _load();
  }

  static const _kReminders = 'om_reminders';
  static const _kMutedTasks = 'om_reminders_muted_tasks';

  final _notify = NotificationService.instance;

  List<Reminder> _reminders = [];
  List<Reminder> get reminders => List.unmodifiable(_reminders);

  /// Scheduled tasks the user has turned the nudge off for. Stored as an opt
  /// out rather than an opt in, because a thing you put on today's timeline at
  /// 4pm is a thing you want to hear about at 4pm.
  Set<String> _mutedTasks = {};
  bool isTaskMuted(String id) => _mutedTasks.contains(id);

  /// Today's timed blocks, kept here so a change to the day reschedules the
  /// nudges. Pushed in from the widget tree, which is the only place that has
  /// the task provider to hand.
  List<Task> _tasks = const [];

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kReminders);
      if (raw != null) {
        _reminders = (jsonDecode(raw) as List)
            .map((e) => Reminder.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
      _mutedTasks = (p.getStringList(_kMutedTasks) ?? const []).toSet();
    } catch (e) {
      debugPrint('[reminders] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
    unawaited(_sync());
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        _kReminders, jsonEncode(_reminders.map((r) => r.toJson()).toList()));
    await p.setStringList(_kMutedTasks, _mutedTasks.toList());
  }

  // ─── Editing ──────────────────────────────────────────────────────────────

  Future<void> add(Reminder r) async {
    _reminders = [..._reminders, r];
    notifyListeners();
    await _persist();
    await _sync();
  }

  Future<void> update(Reminder r) async {
    _reminders = [
      for (final x in _reminders) if (x.id == r.id) r else x,
    ];
    notifyListeners();
    await _persist();
    await _sync();
  }

  Future<void> remove(String id) async {
    _reminders = _reminders.where((r) => r.id != id).toList();
    notifyListeners();
    await _persist();
    await _sync();
  }

  Future<void> setEnabled(String id, bool on) async {
    final found = _reminders.where((r) => r.id == id).firstOrNull;
    if (found == null) return;
    await update(found.copyWith(enabled: on));
  }

  Future<void> setTaskNudge(String taskId, bool on) async {
    if (on) {
      _mutedTasks.remove(taskId);
    } else {
      _mutedTasks.add(taskId);
    }
    notifyListeners();
    await _persist();
    await _sync();
  }

  /// Goal deadlines, nudged at 9am on the day they are due.
  List<Goal> _goals = const [];

  void updateGoals(List<Goal> goals) {
    final live = goals.where((g) => g.completedAt == null).toList();
    final same = live.length == _goals.length &&
        List.generate(live.length, (i) => i).every((i) =>
            live[i].id == _goals[i].id &&
            live[i].targetDate == _goals[i].targetDate);
    if (same) return;
    _goals = live;
    unawaited(_sync());
  }

  /// Called from the widget tree when today's schedule changes.
  void updateTasks(List<Task> tasks) {
    final timed = tasks.where((t) => t.startTime != null && !t.done).toList();
    final same = timed.length == _tasks.length &&
        List.generate(timed.length, (i) => i).every((i) =>
            timed[i].id == _tasks[i].id &&
            timed[i].startTime == _tasks[i].startTime &&
            timed[i].title == _tasks[i].title);
    if (same) return;
    _tasks = timed;
    unawaited(_sync());
  }

  // ─── Handing it all to the OS ─────────────────────────────────────────────

  /// Notification ids for task nudges, offset so they cannot collide with a
  /// reminder's own id.
  int _taskNotificationId(String taskId) => ('task:$taskId').hashCode & 0x7fffffff;

  bool _syncing = false;

  /// The ids we handed the OS last time.
  ///
  /// This exists because `cancelAll` was the obvious way to start a sync from a
  /// clean slate, and it is wrong: it also tears down notifications that have
  /// already been delivered and are sitting unread in the shade. A reminder
  /// that vanishes from your notifications because some unrelated task moved
  /// is worse than one that never arrived, because you saw it and now cannot
  /// find it. So we cancel only what is genuinely no longer wanted, and
  /// re-scheduling an id simply replaces its pending alarm.
  static const _kScheduled = 'om_reminders_scheduled_ids';

  Future<void> _sync() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final p = await SharedPreferences.getInstance();
      final previous = (p.getStringList(_kScheduled) ?? const [])
          .map(int.tryParse)
          .whereType<int>()
          .toSet();
      final wanted = <int>{};

      for (final r in _reminders.where((r) => r.enabled)) {
        wanted.add(r.notificationId);
        await _notify.schedule(
          id: r.notificationId,
          title: r.title,
          body: r.note.isEmpty ? 'you asked me to remind you.' : r.note,
          at: r.nextOccurrence(),
          daily: r.repeat == ReminderRepeat.daily,
        );
      }
      for (final t in _tasks) {
        if (_mutedTasks.contains(t.id)) continue;
        final id = _taskNotificationId(t.id);
        wanted.add(id);
        await _notify.schedule(
          id: id,
          title: t.title,
          body: 'this is the block you set for it.',
          at: t.startTime!,
        );
      }
      for (final g in _goals) {
        final id = ('goal:${g.id}').hashCode & 0x7fffffff;
        wanted.add(id);
        await _notify.schedule(
          id: id,
          title: '${g.title} is due today',
          body: 'the deadline you set for it is today.',
          at: DateTime(g.targetDate.year, g.targetDate.month, g.targetDate.day,
              9, 0),
        );
      }

      for (final gone in previous.difference(wanted)) {
        await _notify.cancel(gone);
      }
      await p.setStringList(
          _kScheduled, wanted.map((i) => i.toString()).toList());
    } catch (e) {
      debugPrint('[reminders] sync failed: $e');
    } finally {
      _syncing = false;
    }
  }

  /// Re-arm everything. Used after the permission is granted, since anything
  /// scheduled before that was refused by the OS.
  Future<void> resync() => _sync();
}
