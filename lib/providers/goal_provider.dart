import 'dart:convert';

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/groq_service.dart';
import '../models/energy_level.dart';
import '../models/goal.dart';
import '../models/task.dart';
import '../services/notification_service.dart';
import 'task_provider.dart';

/// Owns the user's goals and turns each one into a dated, day-by-day plan.
///
/// When a goal is created the user gives a title + a target date; an AI pass
/// breaks the goal into one focused mini-task per working day from today until
/// the deadline. Today's milestone(s) are pushed into [TaskProvider] as
/// goal-tagged tasks so they appear in the day's time-blocks (rendered
/// distinctly), and rolled-up progress is tracked here.
class GoalProvider extends ChangeNotifier {
  GoalProvider(this._tasks) {
    load();
  }

  TaskProvider _tasks;

  static const _kGoals = 'om_goals';

  bool _loaded = false;

  /// The day whose milestones are currently on the timeline. Auto-Schedule and
  /// the week strip both move this, so planning next Tuesday puts *Tuesday's*
  /// goal step on the day rather than today's.
  DateTime _day = DateTime.now();
  DateTime get day => _day;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kGoals);
      if (raw != null) {
        _goals.addAll((jsonDecode(raw) as List)
            .map((g) => Goal.fromJson((g as Map).cast<String, dynamic>())));
      }
    } catch (e) {
      debugPrint('[goals] load failed: $e');
    }
    _loaded = true;
    _injectFor(_day);
    notifyListeners();
  }

  Future<void> _persist() async {
    if (!_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kGoals, jsonEncode(_goals.map((g) => g.toJson()).toList()));
    } catch (e) {
      debugPrint('[goals] save failed: $e');
    }
  }

  /// Re-bound by the ProxyProvider so we always push tasks into the live
  /// [TaskProvider] instance.
  void updateTasks(TaskProvider tasks) {
    _tasks = tasks;
  }

  final List<Goal> _goals = [];
  List<Goal> get goals => List.unmodifiable(_goals);

  bool _busy = false;
  bool get busy => _busy;

  /// Goals still in progress (drive the "goals on the go" counter).
  int get activeCount => _goals.where((g) => !g.isComplete).length;

  /// ── Aggregate achievement (drives the "goal achievement" tracker card) ──
  /// Every goal is a dated sequence of daily steps; achievement is simply how
  /// many of those daily steps have been ticked off across all goals.
  int get totalSteps => _goals.fold(0, (s, g) => s + g.total);
  int get doneSteps => _goals.fold(0, (s, g) => s + g.doneCount);

  /// Overall completion fraction (0..1) across every goal's daily steps.
  double get overallProgress => totalSteps == 0 ? 0 : doneSteps / totalSteps;

  /// Where the plan *should* be by today, weighted by each goal's timeline -
  /// lets the UI say "on track" vs "behind" relative to each deadline.
  double get expectedProgress {
    final now = DateTime.now();
    int total = 0;
    double weighted = 0;
    for (final g in _goals) {
      if (g.total == 0) continue;
      final span = g.targetDate.difference(g.createdAt).inDays + 1;
      final elapsed = now.difference(g.createdAt).inDays + 1;
      final frac = span <= 0 ? 1.0 : (elapsed / span).clamp(0.0, 1.0);
      weighted += frac * g.total;
      total += g.total;
    }
    return total == 0 ? 0 : weighted / total;
  }

  /// True when the user is keeping up with (or ahead of) the expected pace.
  bool get onTrack => overallProgress + 0.001 >= expectedProgress;

  /// Create a goal and break it into a daily plan. [currentEnergy] is the user's
  /// logged vibe right now - the AI uses it to pitch the first day's effort
  /// (gentle on dead days, ambitious on high-energy ones). Returns null on
  /// success or an error message the UI can surface.
  Future<String?> addGoal({
    required String title,
    required DateTime targetDate,
    EnergyLevel? currentEnergy,
    TimeOfDay? dailyStart,
    int dailyMinutes = 60,
  }) async {
    _busy = true;
    notifyListeners();
    try {
      final milestones = await _breakdown(title, targetDate, currentEnergy);
      final goal = Goal(
        id: 'goal-${DateTime.now().microsecondsSinceEpoch}',
        title: title.trim(),
        createdAt: DateTime.now(),
        targetDate: targetDate,
        milestones: milestones,
        dailyStart: dailyStart,
        dailyMinutes: dailyMinutes,
      );
      _goals.add(goal);
      _scheduleDeadlineReminder(goal);
      _injectFor(_day);
      _persist();
      return null;
    } catch (e) {
      return 'Couldn’t break down the goal - please try again.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  void removeGoal(String id) {
    _goals.removeWhere((g) => g.id == id);
    _injectFor(_day);
    _persist();
    notifyListeners();
  }

  /// Tick a whole goal off (or back on) from the Home list - marks every
  /// milestone done/undone and keeps the day's timeline in sync.
  void toggleGoalComplete(String id) {
    final g = _goals.firstWhere((g) => g.id == id, orElse: () => _goals.first);
    final makeDone = !g.isComplete;
    for (final m in g.milestones) {
      m.done = makeDone;
    }
    if (makeDone) _compactFinished();
    _injectFor(_day);
    _persist();
    notifyListeners();
  }

  /// Fire a reminder at the goal's deadline (09:00 on the target day) so the
  /// user gets nudged when a goal is due. Uses the app's shared reminder service.
  void _scheduleDeadlineReminder(Goal goal) {
    final due = DateTime(goal.targetDate.year, goal.targetDate.month, goal.targetDate.day, 9, 0);
    NotificationService().scheduleAlarm(
      id: 'goal-due-${goal.id}'.hashCode,
      title: 'Goal due today: ${goal.title}',
      body: 'Today is your deadline - finish strong! 💪',
      scheduledTime: due,
    );
  }

  /// Keep a goal milestone's done state in sync when its timeline task is ticked.
  void markMilestoneDone(String milestoneId, bool done) {
    for (final g in _goals) {
      for (final m in g.milestones) {
        if (m.id == milestoneId && m.done != done) {
          m.done = done;
          _compactFinished();
          _persist();
          notifyListeners();
          return;
        }
      }
    }
  }

  /// Fold any goal whose last step just got ticked down to a record.
  ///
  /// Done exactly once, at the moment it completes, so the plan is available
  /// right up until it stops being useful and never after.
  void _compactFinished() {
    for (var i = 0; i < _goals.length; i++) {
      final g = _goals[i];
      if (!g.isArchived && g.total > 0 && g.doneCount == g.total) {
        _goals[i] = g.compact();
      }
    }
  }

  /// Finished goals, newest first. Home keeps these behind a disclosure rather
  /// than in the main list.
  List<Goal> get finished {
    final out = _goals.where((g) => g.isComplete).toList();
    out.sort((a, b) =>
        (b.completedAt ?? b.targetDate).compareTo(a.completedAt ?? a.targetDate));
    return out;
  }

  List<Goal> get active => _goals.where((g) => !g.isComplete).toList();

  /// Re-push today's milestones into the task list (call on app/home init).
  void refreshTodayTasks() => _injectFor(DateTime.now());

  /// Put [day]'s goal steps on the timeline, and only [day]'s.
  ///
  /// Each goal was already broken into one dated step per day up to its
  /// deadline, so planning a future day means surfacing that day's step in the
  /// slot the user set aside for the goal - not dragging the whole remaining
  /// plan forward into one afternoon.
  void showDay(DateTime day) {
    if (_sameDay(day, _day)) return;
    _day = day;
    _injectFor(day);
    notifyListeners();
  }

  // ─────────────────────────────────────────────────────────────────────────

  void _injectFor(DateTime day) {
    _day = day;
    final now = DateTime.now();
    final out = <Task>[];
    for (final g in _goals) {
      // A finished goal has no plan left to put on the day.
      if (g.isComplete) continue;
      for (final m in g.milestones) {
        if (_sameDay(m.date, day)) {
          // Land it in the slot the user set aside for this goal. Without a
          // slot it stays unscheduled and auto-schedule places it wherever it
          // fits, as before.
          final slot = g.slotOn(day);
          out.add(Task(
            id: m.id,
            title: m.title,
            time: slot != null ? DateFormat.jm().format(slot) : 'goal',
            energy: m.energy,
            done: m.done,
            goalId: g.id,
            goalTitle: g.title,
            steps: m.steps.map((s) => MicroStep(text: s.text, done: s.done)).toList(),
            scheduled: slot != null,
            startTime: slot,
            duration: slot != null ? g.dailyDuration : null,
          ));
        } else if (m.date.isBefore(now) && !m.done) {
          out.add(Task(
            id: m.id,
            title: m.title,
            time: 'backlog',
            energy: m.energy,
            done: m.done,
            goalId: g.id,
            goalTitle: g.title,
            steps: m.steps.map((s) => MicroStep(text: s.text, done: s.done)).toList(),
            scheduled: false,
          ));
        }
      }
    }
    _tasks.syncGoalTasks(out);
  }

  Future<List<GoalMilestone>> _breakdown(
      String title, DateTime targetDate, EnergyLevel? currentEnergy) async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final totalDays = target.difference(today).inDays + 1; // inclusive, day 1 = today
    final days = totalDays.clamp(1, 60).toInt();

    final energyNote = switch (currentEnergy) {
      EnergyLevel.high =>
        "The user's energy RIGHT NOW is HIGH - make day 1 (today) the most demanding, momentum-building step while they're firing on all cylinders.",
      EnergyLevel.low =>
        "The user's energy RIGHT NOW is LOW - keep day 1 (today) light and very achievable (a 5-15 min warm-up), and ramp up on later days.",
      EnergyLevel.dead =>
        "The user's energy RIGHT NOW is BRAIN-DEAD - make day 1 (today) a tiny, almost-effortless step (think 2-5 minutes) so they can still win today; push the real work to later days.",
      null => 'Pace the plan naturally.',
    };

    final prompt = '''
The user has a goal: "$title".
They want to achieve it within $days day(s), starting today.
$energyNote
Produce a realistic day-by-day plan with ONE focused mini-task per day (you may skip some days for rest if the goal is long - but cover the whole stretch). Order from day 1 (today) to day $days.
For each planned day output an object with:
- "day": 1-based day number from today (1..$days)
- "title": a short, concrete action for that day
- "energy": one of "high", "low", "dead" (mental effort that day's step needs)
- "steps": optional array of 1-3 micro-steps
Respond ONLY with a valid JSON array, no markdown. Example:
[{"day":1,"title":"...","energy":"high","steps":["..."]}]
''';

    final milestones = <GoalMilestone>[];
    try {
      final response = await GroqService.instance.complete([
        {'role': 'system', 'content': 'You are a JSON-only planning API. Only output valid JSON.'},
        {'role': 'user', 'content': prompt},
      ]);

      final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final arr = jsonDecode(cleaned) as List;

      for (final item in arr) {
        final map = item as Map<String, dynamic>;
        final dayNum = (map['day'] is num) ? (map['day'] as num).toInt() : milestones.length + 1;
        final clampedDay = dayNum.clamp(1, days).toInt();
        final date = today.add(Duration(days: clampedDay - 1));

        final eStr = map['energy']?.toString().toLowerCase() ?? '';
        final en = eStr.contains('high')
            ? EnergyLevel.high
            : eStr.contains('dead')
                ? EnergyLevel.dead
                : EnergyLevel.low;

        final stepsJson = map['steps'] as List?;
        final steps = stepsJson?.map((s) => MicroStep(text: s.toString())).toList();

        milestones.add(GoalMilestone(
          id: 'gm-${DateTime.now().microsecondsSinceEpoch}-${milestones.length}',
          title: map['title']?.toString() ?? 'Untitled step',
          date: date,
          energy: en,
          steps: steps,
        ));
      }
    } catch (e) {
      // AI unavailable / bad response - fall back so the goal is never broken.
      debugPrint('goal breakdown via AI failed, using local plan: $e');
    }

    if (milestones.isEmpty) {
      milestones.addAll(_fallbackPlan(title, today, days, currentEnergy));
    }
    return milestones;
  }

  /// A deterministic day-by-day plan used when the AI can't be reached, so a
  /// goal always lands on the timeline with one focused step per day up to the
  /// deadline (ramping from a gentle start to deeper work).
  List<GoalMilestone> _fallbackPlan(
      String title, DateTime today, int days, EnergyLevel? currentEnergy) {
    final out = <GoalMilestone>[];
    for (var d = 0; d < days; d++) {
      // First day matches the user's current energy; later days alternate so the
      // plan mixes deep-focus and lighter days.
      final EnergyLevel en = d == 0
          ? (currentEnergy ?? EnergyLevel.low)
          : (d % 3 == 0
              ? EnergyLevel.dead
              : d.isEven
                  ? EnergyLevel.high
                  : EnergyLevel.low);
      final String stepTitle = d == 0
          ? 'Kick off: $title'
          : d == days - 1
              ? 'Finish & review: $title'
              : 'Day ${d + 1}: make progress on $title';
      out.add(GoalMilestone(
        id: 'gm-${DateTime.now().microsecondsSinceEpoch}-$d',
        title: stepTitle,
        date: today.add(Duration(days: d)),
        energy: en,
      ));
    }
    return out;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
