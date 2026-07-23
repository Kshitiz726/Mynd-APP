import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/community/chat_models.dart';
import '../models/energy_level.dart';
import '../models/task.dart';
import 'alerts_provider.dart';

/// Backlog filter options. `null`-like "all" is represented by [BacklogFilter.all].
enum BacklogFilter { all, high, low, dead }

extension BacklogFilterX on BacklogFilter {
  String get label => switch (this) {
        BacklogFilter.all => 'all',
        BacklogFilter.high => 'high',
        BacklogFilter.low => 'low',
        BacklogFilter.dead => 'brain-dead',
      };

  EnergyLevel? get energy => switch (this) {
        BacklogFilter.all => null,
        BacklogFilter.high => EnergyLevel.high,
        BacklogFilter.low => EnergyLevel.low,
        BacklogFilter.dead => EnergyLevel.dead,
      };
}

/// Owns the task list and all task business logic. The UI never mutates a
/// [Task] directly - it calls these methods so rebuilds stay correct.
class TaskProvider extends ChangeNotifier {
  TaskProvider() : _tasks = _seed() {
    load();
  }

  final List<Task> _tasks;
  BacklogFilter _filter = BacklogFilter.all;

  // ─────────────────────── Persistence ───────────────────────
  //
  // The day survives a relaunch. Every mutation in this class ends in
  // [notifyListeners], so rather than sprinkling save calls through thirty
  // methods we hook the notification itself and debounce the write - a drag
  // gesture fires dozens of notifications a second and none of them deserve
  // their own disk round-trip.

  static const _kTasks = 'om_tasks';

  bool _loaded = false;
  bool get loaded => _loaded;

  Timer? _saveDebounce;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kTasks);
      if (raw != null) {
        final restored = (jsonDecode(raw) as List)
            .map((t) => Task.fromJson((t as Map).cast<String, dynamic>()))
            .toList();
        // Goal-derived tasks are re-injected from GoalProvider on launch, so
        // restoring them here too would duplicate every milestone.
        _tasks
          ..clear()
          ..addAll(restored.where((t) => !t.isGoalTask));
      }
    } catch (e) {
      debugPrint('[tasks] load failed: $e');
    }
    _loaded = true;
    // Deliberately not the overridden [notifyListeners]: nothing changed that
    // storage does not already know about, so scheduling a save here would
    // write the file back to itself on every cold start.
    super.notifyListeners();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    if (!_loaded) return; // never write back over storage we have not read yet
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kTasks, jsonEncode(_tasks.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('[tasks] save failed: $e');
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    // A pending debounce would be lost, and the last edit before backgrounding
    // is exactly the one worth keeping.
    _persist();
    super.dispose();
  }

  BacklogFilter get filter => _filter;
  List<Task> get all => List.unmodifiable(_tasks);

  int get totalToday => _tasks.where((t) => !t.isChunk && !t.isAnchor).length;
  int get doneCount => _tasks.where((t) => !t.isChunk && !t.isAnchor && t.done).length;
  int get goalsOnTheGo => 0;

  static DateTime _todayDate() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  /// The day the timeline is showing. Defaults to today (date-only, so it lines
  /// up exactly with the device's calendar day); the week strip moves it.
  DateTime _selectedDate = _todayDate();
  DateTime get selectedDate => _selectedDate;
  bool get viewingToday => _isSameDay(_selectedDate, DateTime.now());

  void selectDate(DateTime day) {
    if (_isSameDay(day, _selectedDate)) return;
    _selectedDate = day;
    notifyListeners();
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Blocks scheduled on [day], in time order.
  ///
  /// [includeDone] keeps finished blocks in the list. The timeline wants them -
  /// ticking something off should strike it through where it sits, not delete
  /// your afternoon - and so does any overlap arithmetic, because an hour you
  /// already spent is still an hour that is taken. "What is next" does not.
  List<Task> scheduleOn(DateTime day, {bool includeDone = false}) {
    final list = _tasks
        .where((t) =>
            t.scheduled &&
            !t.isMissed &&
            t.startTime != null &&
            (includeDone || !t.done) &&
            _isSameDay(t.startTime!, day))
        .toList();
    list.sort((a, b) => a.startTime!.compareTo(b.startTime!));
    return list;
  }

  /// What the timeline renders: the selected day, not necessarily today,
  /// finished blocks included so they can be shown struck through.
  List<Task> get daySchedule => scheduleOn(_selectedDate, includeDone: true);

  /// Today specifically. Packing, conflict checks and "up next" must not follow
  /// the user's browsing around the week.
  List<Task> get todaySchedule => scheduleOn(DateTime.now());

  Task? get upNext {
    final now = DateTime.now();
    for (final t in todaySchedule) {
      if (t.endTime != null && t.endTime!.isAfter(now)) {
        return t;
      }
    }
    return null;
  }

  /// The block the clock is actually inside right now. Anchors are excluded:
  /// "wake up" and "sleep" are the shape of the day, not work you focus on.
  Task? get nowBlock {
    final now = DateTime.now();
    for (final t in todaySchedule) {
      if (t.isAnchor) continue;
      final end = t.endTime;
      if (end != null && !t.startTime!.isAfter(now) && end.isAfter(now)) return t;
    }
    return null;
  }

  /// The next real block still to come today, for the gap between blocks.
  Task? get nextBlock {
    final now = DateTime.now();
    for (final t in todaySchedule) {
      if (t.isAnchor) continue;
      if (t.startTime!.isAfter(now)) return t;
    }
    return null;
  }

  /// Ids of parent tasks that currently have chunk blocks on the timeline, so we
  /// can keep the parent itself out of the backlog while its chunks are live.
  Set<String> get _chunkedParentIds =>
      _tasks.where((t) => t.isChunk).map((t) => t.chunkOf!).toSet();

  /// Backlog = unscheduled (or missed) tasks matching the active filter, not done.
  /// Chunk blocks and parents that have live chunks are hidden here.
  List<Task> get backlog {
    final energy = _filter.energy;
    final chunkedParents = _chunkedParentIds;
    return _tasks
        .where((t) =>
            !t.isAnchor &&
            !t.isChunk &&
            !chunkedParents.contains(t.id) &&
            (!t.scheduled || t.isMissed) &&
            !t.done &&
            (energy == null || t.energy == energy))
        .toList(growable: false);
  }

  void setFilter(BacklogFilter f) {
    if (f == _filter) return;
    _filter = f;
    notifyListeners();
  }

  /// Fired the moment a task is checked off, so the streak can record *today*.
  ///
  /// An event rather than the provider exposing "how many are done", because
  /// that count belongs to whichever day is being looked at - scrolling back
  /// to last Tuesday would otherwise credit today.
  VoidCallback? onTaskCompleted;

  void toggleDone(Task task) {
    task.done = !task.done;
    if (task.done) onTaskCompleted?.call();
    // When every chunk of a heavy task is checked off, mark the parent done and
    // clear the now-redundant chunk blocks so it reads as a single finished item.
    if (task.isChunk) {
      final siblings = _tasks.where((t) => t.chunkOf == task.chunkOf).toList();
      if (siblings.isNotEmpty && siblings.every((s) => s.done)) {
        final parent = _firstById(task.chunkOf!);
        if (parent != null) {
          parent.done = true;
          parent.scheduled = false;
          parent.startTime = null;
        }
        _tasks.removeWhere((t) => t.chunkOf == task.chunkOf);
      }
    }
    notifyListeners();
  }

  void toggleExpanded(Task task) {
    task.expanded = !task.expanded;
    notifyListeners();
  }

  void toggleStep(Task task, MicroStep step) {
    step.done = !step.done;
    notifyListeners();
  }

  void editTask(String id, String newTitle, EnergyLevel newEnergy) {
    final task = _firstById(id);
    if (task != null) {
      // we can't cleanly update `final title` and `final energy` if they are final.
      // Wait, let's check models/task.dart. Oh, `title` and `energy` are final.
      // I'll need to mutate them or replace the task. I will replace the task object!
      final index = _tasks.indexOf(task);
      if (index != -1) {
        _tasks[index] = Task(
          id: task.id,
          title: newTitle,
          energy: newEnergy,
          time: task.time,
          done: task.done,
          expanded: task.expanded,
          scheduled: task.scheduled,
          startTime: task.startTime,
          duration: task.duration,
          isAnchor: task.isAnchor,
          goalId: task.goalId,
          goalTitle: task.goalTitle,
          chunkOf: task.chunkOf,
          chunkIndex: task.chunkIndex,
          chunkCount: task.chunkCount,
          steps: task.steps,
        );
        notifyListeners();
      }
    }
  }

  /// "Add to my day": drop [task] onto the day the user is currently looking at,
  /// not always today. Standing on the 23rd and adding a task schedules it on
  /// the 23rd. A past day can't be planned, so it falls back to today.
  void schedule(Task task) {
    final day = canPlan(_selectedDate) ? _selectedDate : DateTime.now();
    _placeOn(task, day);
    notifyListeners();
  }

  /// Finds the next free slot on [day] (08:00-21:00) and pins [task] there. On
  /// today it starts from NOW; on a future day it starts from 08:00.
  void _placeOn(Task task, DateTime day) {
    final now = DateTime.now();
    task.duration ??= const Duration(hours: 1);
    const startHour = 8;
    const endHour = 21;
    final packingToday = _isSameDay(day, now);

    final text = task.title.toLowerCase();
    final preferEvening = text.contains('call') || text.contains('family');

    DateTime searchStart =
        packingToday ? now : DateTime(day.year, day.month, day.day, startHour, 0);
    if (preferEvening && searchStart.hour < 17) {
      searchStart = DateTime(day.year, day.month, day.day, 17, 0);
    }
    if (searchStart.hour >= endHour) {
      searchStart = DateTime(searchStart.year, searchStart.month, searchStart.day + 1, startHour, 0);
    } else if (searchStart.hour < startHour) {
      searchStart = DateTime(searchStart.year, searchStart.month, searchStart.day, startHour, 0);
    }

    final occupied = scheduleOn(searchStart, includeDone: true);
    DateTime proposedStart = searchStart;
    for (final t in occupied) {
      if (!proposedStart.add(task.duration!).isAfter(t.startTime!)) break;
      if (t.endTime!.isAfter(proposedStart)) proposedStart = t.endTime!;
      if (proposedStart.hour >= endHour) {
        proposedStart = DateTime(proposedStart.year, proposedStart.month, proposedStart.day + 1, startHour, 0);
      }
    }

    task.startTime = proposedStart;
    task.scheduled = true;
  }

  /// Round [t] up to the next 5-minute mark so auto-placed blocks land on clean
  /// times rather than e.g. 2:43 PM.
  DateTime _roundUpToFive(DateTime t) {
    final rem = t.minute % 5;
    if (rem == 0 && t.second == 0) return DateTime(t.year, t.month, t.day, t.hour, t.minute);
    return DateTime(t.year, t.month, t.day, t.hour, t.minute).add(Duration(minutes: 5 - rem));
  }

  /// Auto-fills the day starting from **NOW** (or the wake time if we haven't
  /// reached it yet), packing un-done tasks - including goal-derived ones - into
  /// the remaining time before wind-down. Past blocks are left in the backlog,
  /// and any heavy task is broken into focus-sized chunks so it still fits.
  void autoScheduleDay(
    TimeOfDay wakeUp,
    TimeOfDay sleep,
    AlertsProvider alerts,
    String ringtone, {
    DateTime? day,
  }) {
    final now = DateTime.now();
    final target = day ?? now;
    // The past is a record - you can't plan a day that's already gone.
    if (!canPlan(target)) return;
    final packingToday = _isSameDay(target, now);
    final floor = packingToday ? now : DateTime(target.year, target.month, target.day);

    // Dead simple: lay the wake-up and sleep bookends on the day, then drop
    // everything in the backlog between them as blocks - one block per task,
    // back to back, in order. No splitting a task into chunks, no clever
    // packing. Exactly "put my backlog on this day, with my wake/sleep times".

    // Clear this day's own blocks first so re-running just re-lays them (and
    // sweep any leftover chunks a previous version left on this day).
    _tasks.removeWhere((t) =>
        (t.id == 'wake_anchor' || t.id == 'sleep_anchor' || t.id.startsWith('habit-') || t.isChunk) &&
        (t.startTime == null || _isSameDay(t.startTime!, target)));
    for (final t in _tasks) {
      if (!t.done && !t.isAnchor && !t.isChunk && t.startTime != null && _isSameDay(t.startTime!, target)) {
        t.scheduled = false;
        t.startTime = null;
      }
    }

    final wakeTime = DateTime(target.year, target.month, target.day, wakeUp.hour, wakeUp.minute);
    var sleepTimeFull = DateTime(target.year, target.month, target.day, sleep.hour, sleep.minute);
    if (!sleepTimeFull.isAfter(wakeTime)) sleepTimeFull = sleepTimeFull.add(const Duration(days: 1));
    final windDown = sleepTimeFull.subtract(const Duration(minutes: 30));

    // Wake-up bookend, unless that time has already passed today.
    if (wakeTime.isAfter(floor)) {
      _tasks.add(Task(id: 'wake_anchor', title: 'Wake Up Routine', time: 'Morning', energy: EnergyLevel.high, isAnchor: true)
        ..scheduled = true
        ..startTime = wakeTime
        ..duration = const Duration(minutes: 30));
      alerts.addLocalReminder(AppNotification(
        id: 'alm-wake', kind: 'alarm', read: false,
        payload: {'title': 'Wake Up', 'time': DateFormat.jm().format(wakeTime)},
      ));
    }

    // Everything in the backlog now (unscheduled or missed, not done).
    final items = _tasks
        .where((t) => !t.isAnchor && !t.isChunk && !t.done && (!t.scheduled || t.isMissed))
        .toList();
    // A gentle order: high-energy first, brain-dead last. Nothing more.
    items.sort((a, b) => a.energy.index.compareTo(b.energy.index));

    // Work begins after the wake routine when we placed one (its 30-minute
    // block is known, so derive the start directly rather than looking the
    // anchor up by id - several days can share the 'wake_anchor' id, and the
    // lookup returned the wrong day's block, letting the first task overlap
    // the wake routine). Otherwise (today, already past wake) start from now.
    DateTime cursor = wakeTime.isAfter(floor)
        ? wakeTime.add(const Duration(minutes: 30))
        : _roundUpToFive(floor);

    for (final t in items) {
      final dur = t.duration ??= const Duration(hours: 1);
      t.startTime = cursor;
      t.scheduled = true;
      alerts.addLocalReminder(AppNotification(
        id: 'rem-${t.id}', kind: 'reminder', read: false,
        payload: {'title': t.title, 'time': DateFormat.jm().format(cursor)},
      ));
      cursor = cursor.add(dur);
    }

    // Sleep / wind-down bookend.
    if (windDown.isAfter(floor)) {
      _tasks.add(Task(id: 'sleep_anchor', title: 'Wind Down / Sleep', time: 'Night', energy: EnergyLevel.dead, isAnchor: true)
        ..scheduled = true
        ..startTime = windDown
        ..duration = const Duration(minutes: 30));
      alerts.addLocalReminder(AppNotification(
        id: 'alm-sleep', kind: 'alarm', read: false,
        payload: {'title': 'Sleep', 'time': DateFormat.jm().format(sleepTimeFull)},
      ));
    }

    notifyListeners();
  }

  /// Repack a manually reordered timeline. Available slots stay put - only the
  /// task blocks move - so packing starts at the first block's existing start
  /// (clamped to NOW) and lays the reordered blocks back-to-back from there.
  /// Repack [ordered] back-to-back inside the window [windowStart]..[windowEnd].
  ///
  /// Anchors (wake, sleep) are never passed in: they are fixed points, and the
  /// old behaviour of packing them along with everything else is what threw the
  /// whole day out of alignment. Anything that no longer fits before
  /// [windowEnd] is returned to the backlog rather than silently overflowing
  /// past bedtime.
  void recalculateSchedule(
    List<Task> ordered,
    DateTime windowStart,
    DateTime windowEnd,
    String ringtone,
  ) {
    if (ordered.isEmpty) return;

    final now = DateTime.now();
    // Never lay a block in the past on today's timeline.
    DateTime cursor = windowStart.isBefore(now) && _isSameDay(windowStart, now)
        ? _roundUpToFive(now)
        : windowStart;

    for (final t in ordered) {
      if (t.isAnchor) continue;
      final dur = t.duration ??= const Duration(hours: 1);
      if (cursor.add(dur).isAfter(windowEnd)) {
        t.scheduled = false;
        t.startTime = null;
        continue;
      }
      t.startTime = cursor;
      t.scheduled = true;
      cursor = cursor.add(dur);
    }
    notifyListeners();
  }

  /// Whether [day] can still be planned. The past is a record, not a plan.
  bool canPlan(DateTime day) {
    final today = DateTime.now();
    final d = DateTime(day.year, day.month, day.day);
    return !d.isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Everything completed on [day], newest last, for the read-only past view.
  List<Task> doneOn(DateTime day) {
    final list = _tasks
        .where((t) => t.done && t.startTime != null && _isSameDay(t.startTime!, day))
        .toList();
    list.sort((a, b) => a.startTime!.compareTo(b.startTime!));
    return list;
  }

  /// Headline numbers for a past day: how much was finished, and how long it took.
  ({int done, int missed, Duration focused}) statsFor(DateTime day) {
    final finished = doneOn(day);
    final missed = _tasks
        .where((t) =>
            !t.done &&
            t.startTime != null &&
            _isSameDay(t.startTime!, day) &&
            !t.isAnchor)
        .length;
    var focused = Duration.zero;
    for (final t in finished) {
      if (!t.isAnchor) focused += t.duration ?? const Duration(hours: 1);
    }
    return (done: finished.where((t) => !t.isAnchor).length, missed: missed, focused: focused);
  }

  /// Drop a backlog [task] into a tapped Available slot starting at [start],
  /// trimming its duration to [maxDuration] so it fits the gap exactly.
  void fillSlot(Task task, DateTime start, Duration maxDuration, {String ringtone = 'Default'}) {
    final dur = (task.duration ?? const Duration(hours: 1));
    final fit = dur > maxDuration ? maxDuration : dur;
    setTaskTime(task, start, start.add(fit), ringtone: ringtone);
  }

  void addQuickTask(String title, EnergyLevel energy) {
    _tasks.insert(
      0,
      Task(
        id: 'task-${DateTime.now().microsecondsSinceEpoch}',
        title: title,
        time: 'today',
        energy: energy,
      ),
    );
    notifyListeners();
  }

  void addTasks(List<Task> newTasks) {
    _tasks.insertAll(0, newTasks);
    notifyListeners();
  }

  /// Returns the first already-scheduled block that [start]-[end] would overlap
  /// (ignoring [task] itself), or null when the window is free. Used to guard
  /// manual time edits so a block can only land in an actually-empty slot.
  Task? conflictFor(Task task, DateTime start, DateTime end) {
    for (final t in scheduleOn(start, includeDone: true)) {
      if (t.id == task.id) continue;
      final ts = t.startTime, te = t.endTime;
      if (ts == null || te == null) continue;
      // Half-open overlap: [start,end) intersects [ts,te).
      if (start.isBefore(te) && end.isAfter(ts)) return t;
    }
    return null;
  }

  /// Move (or resize) [task] to [start]-[end] and let the rest of the day give
  /// way, instead of refusing the edit because something is in the way.
  ///
  /// The moved block is a pin: it lands exactly where the user put it. Every
  /// other block keeps its own duration and slides:
  ///
  /// * blocks that were **after** the pin sweep forward from the pin's new end,
  ///   each keeping the gap it already had from the block before it. A run of
  ///   touching blocks therefore stays touching and follows the pin in *both*
  ///   directions, while a block with real free time in front of it keeps its
  ///   own time and only moves if the pin would actually collide with it - so
  ///   nudging the morning never quietly drags a 5pm appointment earlier;
  /// * blocks that were **before** the pin sweep backward from the pin's new
  ///   start, so dragging a block earlier pulls its predecessors back rather
  ///   than double-booking them;
  /// * a predecessor that no longer fits before [windowStart] is not dropped -
  ///   it is re-queued after the pin, which is the only rearrangement that
  ///   keeps the day both continuous and lossless.
  ///
  /// Returns how far the day now runs past [windowEnd] (zero when it still
  /// fits), so the caller can say so rather than silently booking past bedtime.
  Duration rippleTaskTime(
    Task task,
    DateTime start,
    DateTime end,
    DateTime windowStart,
    DateTime windowEnd, {
    String ringtone = 'Default',
  }) {
    if (!end.isAfter(start)) return Duration.zero;

    // Everything else on the day, in the order it currently sits. Finished
    // blocks included: the time they occupy is still occupied.
    final others = scheduleOn(start, includeDone: true)
        .where((t) => t.id != task.id && !t.isAnchor)
        .toList();

    final before = <Task>[];
    final after = <Task>[];
    for (final t in others) {
      (t.startTime!.isBefore(start) ? before : after).add(t);
    }

    // The gap each following block had in front of it, measured before anything
    // moves. Zero means it was flush against its predecessor (or against the
    // pin), which is what makes a run of blocks travel together.
    final gapBefore = <String, Duration>{};
    var prevEnd = task.endTime ?? start;
    for (final t in after) {
      final gap = t.startTime!.difference(prevEnd);
      gapBefore[t.id] = gap.isNegative ? Duration.zero : gap;
      prevEnd = t.endTime!;
    }

    task.startTime = start;
    task.duration = end.difference(start);
    task.scheduled = true;

    // ── Backward sweep: predecessors end no later than the pin starts. ──
    final displaced = <Task>[];
    var cursor = start;
    for (final t in before.reversed) {
      final dur = t.duration ??= const Duration(hours: 1);
      final newEnd = t.endTime!.isAfter(cursor) ? cursor : t.endTime!;
      final newStart = newEnd.subtract(dur);
      if (newStart.isBefore(windowStart)) {
        // No room left in the morning: this one goes after the pin instead.
        displaced.add(t);
        continue;
      }
      t.startTime = newStart;
      cursor = newStart;
    }

    // ── Forward sweep: everything after the pin, back-to-back but never
    // earlier than where it already was. ──
    cursor = end;
    for (final t in [...displaced.reversed, ...after]) {
      final dur = t.duration ??= const Duration(hours: 1);
      // No recorded gap means the block came from the morning (displaced), so
      // it lands flush against the cursor.
      final gap = gapBefore[t.id] ?? Duration.zero;
      final DateTime newStart;
      if (gap == Duration.zero) {
        // Flush: travels with the block in front of it, forwards or back.
        newStart = cursor;
      } else {
        // It had breathing room, so it keeps its time unless the cursor has
        // caught up with it; the gap absorbs the rest of the shift.
        newStart = t.startTime!.isBefore(cursor) ? cursor : t.startTime!;
      }
      t.startTime = newStart;
      t.scheduled = true;
      cursor = newStart.add(dur);
    }

    // The OS schedule is not touched here. RemindersProvider watches the day
    // and re-arms everything whenever a block moves, so there is one place
    // that decides what the phone is going to say and when.

    notifyListeners();
    return cursor.isAfter(windowEnd) ? cursor.difference(windowEnd) : Duration.zero;
  }

  /// Insert a brand-new block at [start] and push the rest of the day down.
  /// This is how a user drops their own task into the middle of an
  /// auto-scheduled day without re-planning it by hand.
  Duration insertTaskAt(
    Task task,
    DateTime start,
    Duration duration,
    DateTime windowStart,
    DateTime windowEnd, {
    String ringtone = 'Default',
  }) {
    task.duration = duration;
    task.startTime = start;
    task.scheduled = true;
    if (_firstById(task.id) == null) _tasks.insert(0, task);
    return rippleTaskTime(
      task,
      start,
      start.add(duration),
      windowStart,
      windowEnd,
      ringtone: ringtone,
    );
  }

  /// User-driven edit of a scheduled block's start/end. Keeps the task on the
  /// timeline and reschedules its alarm.
  void setTaskTime(Task task, DateTime start, DateTime end, {String ringtone = 'Default'}) {
    if (!end.isAfter(start)) return;
    task.startTime = start;
    task.duration = end.difference(start);
    task.scheduled = true;

    notifyListeners();
  }

  /// Replaces the set of goal-derived tasks with [goalTasks] (idempotent by id),
  /// preserving the done/scheduling state of any that already existed, then
  /// auto-places any that aren't on the timeline yet so they show in a block.
  void syncGoalTasks(List<Task> goalTasks) {
    for (final t in goalTasks) {
      final existing = _firstById(t.id);
      if (existing != null) {
        t.done = existing.done;
        t.scheduled = existing.scheduled;
        t.startTime = existing.startTime;
        t.duration = existing.duration;
      }
    }
    _tasks.removeWhere((t) => t.isGoalTask);
    _tasks.addAll(goalTasks);

    // Place any not-yet-scheduled goal tasks onto the day so they land in a block.
    for (final t in _tasks.where((t) => t.isGoalTask && !t.scheduled && !t.done && t.time != 'backlog')) {
      _place(t);
    }
    notifyListeners();
  }

  Task? _firstById(String id) {
    for (final t in _tasks) {
      if (t.id == id) return t;
    }
    return null;
  }

  /// Finds the next free slot (08:00-21:00) on today for [task] and pins it - the
  /// core of [schedule] without the extra notify, for batch use (goal tasks).
  void _place(Task task) => _placeOn(task, DateTime.now());

  /// Permanently remove [task] - the honest "I'm never doing this" that the
  /// backlog needs alongside "not today". Also clears any chunk blocks it spun
  /// off, so deleting a heavy task doesn't leave orphan pieces on the timeline.
  void deleteTask(String id) {
    _tasks.removeWhere((t) => t.id == id || t.chunkOf == id);
    notifyListeners();
  }

  /// "Not today." Pulls [task] off the timeline and drops it back in the
  /// backlog, free of a time.
  ///
  /// Deliberately not the same as ticking it and not the same as deleting it:
  /// the honest answer to most blocks at the end of a day is "it did not
  /// happen", and the thing an ADHD brain needs then is for the task to still
  /// exist without a failed timestamp attached to it.
  void dismissToBacklog(Task task) {
    task.scheduled = false;
    task.startTime = null;
    task.done = false;
    notifyListeners();
  }

  /// Roll a goal task's completion back into the timeline (used by the timeline
  /// check toggle so goal progress stays accurate).
  void setDone(Task task, bool done) {
    task.done = done;
    notifyListeners();
  }

  static List<Task> _seed() => [];
}
