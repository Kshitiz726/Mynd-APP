import '../../models/coach_context.dart';
import '../../models/energy_level.dart';
import '../../providers/energy_provider.dart';
import '../../providers/focus_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import 'coach_memory_service.dart';

/// Assembles a [CoachContext] by reading from all live in-memory providers
/// plus the persistent [CoachMemoryService].
///
/// This runs before *every* Groq API call so the coach always has a
/// fresh snapshot of the user's current state. It's intentionally cheap
/// (no I/O, providers already hold the data) so calling it every turn is fine.
class CoachContextBuilder {
  CoachContextBuilder._();
  static final CoachContextBuilder instance = CoachContextBuilder._();

  // ─── Public API ───────────────────────────────────────────────────────────

  /// [healthConsent] decides whether the health-related half of this snapshot
  /// is assembled at all.
  ///
  /// Five of these fields describe someone's mental state rather than their
  /// to-do list: the energy level, the mood logs, the parked brain dumps, the
  /// rolling memory of what has been discussed, and the patterns derived from
  /// all of it. Without consent they are not built, so there is nothing for a
  /// later stage to leak - the prompt builder is handed a context in which
  /// that information does not exist, rather than one it is trusted to skip.
  ///
  /// The other half still goes: tasks, habits, focus stats, the name and the
  /// brevity preference. A coach that can still see your backlog is the app
  /// working as promised for someone who declined, which is the difference
  /// between an optional consent and a compulsory one wearing a checkbox.
  CoachContext build({
    required EnergyProvider energy,
    required TaskProvider tasks,
    required HabitProvider habits,
    required FocusProvider focus,
    required SettingsProvider settings,
    required String userName,
    required bool healthConsent,
    String userMemory = '',
  }) {
    final memory = CoachMemoryService.instance;

    return CoachContext(
      userName: userName.isNotEmpty ? userName : 'friend',
      // 'unknown' rather than a guess: the prompt already handles not knowing,
      // and substituting a plausible default would be inventing the very thing
      // consent was withheld for.
      currentEnergyLevel: healthConsent ? _energyLabel(energy.current) : 'unknown',
      recentMoodLogs: const [], // populated from Firebase when integrated
      recentBrainDumps: healthConsent ? _buildBrainDumps(memory) : const [],
      todayTasks: _buildTaskSummaries(tasks),
      habitProgress: _buildHabitProgress(habits),
      focusStatistics: _buildFocusStats(focus),
      // The user's own memory leads: it is the durable picture of who they
      // are, where the session memo is only what was said last time.
      previousConversationSummary: !healthConsent
          ? ''
          : [
              if (userMemory.isNotEmpty) userMemory,
              if (memory.memorySummary.isNotEmpty)
                'From your last sessions together:\n${memory.memorySummary}',
            ].join('\n\n'),
      userPreferences: CoachUserPreferences(
        prefersBrevity: settings.lowStim,
        preferredName: userName.isNotEmpty ? userName : null,
      ),
      detectedPatterns: !healthConsent
          ? const []
          : _detectPatterns(
              energy: energy.current,
              tasks: tasks,
              habits: habits,
              memory: memory,
            ),
    );
  }

  // ─── Sub-builders ─────────────────────────────────────────────────────────

  String _energyLabel(EnergyLevel level) => switch (level) {
        EnergyLevel.high => 'high',
        EnergyLevel.low => 'low',
        EnergyLevel.dead => 'brain-dead',
      };

  List<BrainDumpEntry> _buildBrainDumps(CoachMemoryService memory) {
    return memory.brainDumps.take(3).map((d) {
      return BrainDumpEntry(
        text: d['text'] ?? '',
        capturedAt: DateTime.tryParse(d['at'] ?? '') ?? DateTime.now(),
      );
    }).toList();
  }

  List<TaskSummary> _buildTaskSummaries(TaskProvider tasks) {
    // The coach only ever knows about *today*. Tasks the user has parked on a
    // future day (e.g. tapping "24 July" and auto-scheduling there) must not
    // leak into the conversation - talking to Mynd on the 22nd should surface
    // the 22nd's plan and mood, nothing that lives days ahead. Because these
    // are read live from the provider against DateTime.now(), the picture also
    // "cleans" itself every midnight for free: yesterday's blocks simply stop
    // matching today, and only the rolling summary carries context forward.
    final today = tasks.todaySchedule.where((t) => !t.isAnchor);
    final backlog = tasks.backlog; // undated, "keeps not happening" - fair game
    return [...today, ...backlog].take(8).map((t) {
      return TaskSummary(
        title: t.title,
        energyLevel: t.energy.label,
        isDone: t.done,
        dueAt: t.startTime, // today's blocks carry their time; backlog is null
      );
    }).toList();
  }

  HabitProgress _buildHabitProgress(HabitProvider habits) {
    int total = 0;
    int done = 0;
    String? longestName;
    int longestDays = 0;

    for (final board in habits.boards) {
      for (final habit in board.items) {
        total++;
        if (habit.done) done++;
        // Streak tracking - seeded data uses 0; wire to persistence later.
        if (0 > longestDays) {
          longestDays = 0;
          longestName = habit.name;
        }
      }
    }

    return HabitProgress(
      completedToday: done,
      totalHabits: total,
      longestStreakName: longestName,
      longestStreakDays: longestDays,
    );
  }

  FocusStatistics _buildFocusStats(FocusProvider focus) {
    // FocusProvider owns the live session; completed sessions would come from
    // a persistent store. For now we expose what we can.
    final minutesFocused = focus.isActive
        ? (focus.activeMode!.minutes -
            (focus.secondsRemaining ~/ 60))
        : 0;

    return FocusStatistics(
      sessionsToday: 0, // increment from persistence
      minutesFocusedToday: minutesFocused,
      currentStreakDays: 0,
    );
  }

  // ─── Pattern detection ────────────────────────────────────────────────────

  /// Lightweight heuristics that generate human-readable observations.
  /// These drop straight into the context prompt as "things to notice."
  List<String> _detectPatterns({
    required EnergyLevel energy,
    required TaskProvider tasks,
    required HabitProvider habits,
    required CoachMemoryService memory,
  }) {
    final patterns = <String>[];

    // Overwhelm: many undone tasks + low energy. Scoped to today's plan plus the
    // undated backlog - the load the user is actually carrying *now*, not blocks
    // they deliberately pushed to a later day.
    final undone = tasks.todaySchedule.where((t) => !t.isAnchor && !t.done).length +
        tasks.backlog.length;
    if (undone >= 5 && energy != EnergyLevel.high) {
      patterns.add(
        'The user has $undone unfinished tasks and is not at high energy - '
        'cognitive load is likely high. Help reduce the pile, not add to it.',
      );
    }

    // Brain-dead energy + lots to do
    if (energy == EnergyLevel.dead && undone > 2) {
      patterns.add(
        'The user is at brain-dead energy with tasks still pending. '
        'Responses should be especially gentle and minimal.',
      );
    }

    // No habits completed yet today
    int totalHabits = 0;
    int doneHabits = 0;
    for (final board in habits.boards) {
      for (final h in board.items) {
        totalHabits++;
        if (h.done) doneHabits++;
      }
    }
    if (totalHabits > 0 && doneHabits == 0) {
      patterns.add("The user hasn't checked off any habits yet today.");
    }

    // Previous session pattern from memory
    final memo = memory.memorySummary.toLowerCase();
    if (memo.contains('overwhelm') || memo.contains('stuck')) {
      patterns.add(
        'In previous sessions, overwhelm and feeling stuck have come up. '
        'Be aware this may surface again - acknowledge before solving.',
      );
    }

    return patterns;
  }
}
