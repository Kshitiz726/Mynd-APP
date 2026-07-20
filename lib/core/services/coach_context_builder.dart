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

  CoachContext build({
    required EnergyProvider energy,
    required TaskProvider tasks,
    required HabitProvider habits,
    required FocusProvider focus,
    required SettingsProvider settings,
    required String userName,
  }) {
    final memory = CoachMemoryService.instance;

    return CoachContext(
      userName: userName.isNotEmpty ? userName : 'friend',
      currentEnergyLevel: _energyLabel(energy.current),
      recentMoodLogs: const [], // populated from Firebase when integrated
      recentBrainDumps: _buildBrainDumps(memory),
      todayTasks: _buildTaskSummaries(tasks),
      habitProgress: _buildHabitProgress(habits),
      focusStatistics: _buildFocusStats(focus),
      previousConversationSummary: memory.memorySummary,
      userPreferences: CoachUserPreferences(
        prefersBrevity: settings.lowStim,
        preferredName: userName.isNotEmpty ? userName : null,
      ),
      detectedPatterns: _detectPatterns(
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
    return tasks.all.take(8).map((t) {
      return TaskSummary(
        title: t.title,
        energyLevel: t.energy.label,
        isDone: t.done,
        dueAt: null, // wire to due date when model supports it
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

    // Overwhelm: many undone tasks + low energy
    final undone = tasks.all.where((t) => !t.done).length;
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
