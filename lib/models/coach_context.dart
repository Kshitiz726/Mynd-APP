/// The structured snapshot handed to the coaching pipeline before every
/// response. Each field is already trimmed/summarized by the time it lands
/// here - this is the *context*, not the raw database rows. See
/// [CoachContextBuilder] for how it's assembled and
/// [CoachPromptBuilder] for how it becomes prompt text.
class CoachContext {
  const CoachContext({
    required this.userName,
    required this.currentEnergyLevel,
    required this.recentMoodLogs,
    required this.recentBrainDumps,
    required this.todayTasks,
    required this.habitProgress,
    required this.focusStatistics,
    required this.previousConversationSummary,
    required this.userPreferences,
    required this.detectedPatterns,
  });

  final String userName;

  /// "high" | "low" | "brain-dead" - mirrors [EnergyLevel].
  final String currentEnergyLevel;

  final List<MoodLogEntry> recentMoodLogs;
  final List<BrainDumpEntry> recentBrainDumps;
  final List<TaskSummary> todayTasks;
  final HabitProgress habitProgress;
  final FocusStatistics focusStatistics;

  /// Rolling summary of everything said in prior sessions - never the raw
  /// transcript. Produced by [CoachMemoryService.summarizeConversation].
  final String previousConversationSummary;

  final CoachUserPreferences userPreferences;

  /// Lightweight, human-readable observations surfaced by the pattern
  /// heuristics ("overwhelm has come up a lot this week"). Plain strings on
  /// purpose - they get dropped straight into the context prompt and the
  /// model should treat them as something *noticed*, not a directive.
  final List<String> detectedPatterns;
}

class MoodLogEntry {
  const MoodLogEntry({required this.mood, required this.intensity, required this.loggedAt, this.note});

  final String mood;

  /// 1-5.
  final int intensity;
  final DateTime loggedAt;
  final String? note;
}

class BrainDumpEntry {
  const BrainDumpEntry({required this.text, required this.capturedAt, this.tags = const []});

  final String text;
  final DateTime capturedAt;
  final List<String> tags;
}

class TaskSummary {
  const TaskSummary({required this.title, required this.energyLevel, required this.isDone, this.dueAt});

  final String title;
  final String energyLevel;
  final bool isDone;
  final DateTime? dueAt;
}

class HabitProgress {
  const HabitProgress({required this.completedToday, required this.totalHabits, required this.longestStreakName, required this.longestStreakDays});

  final int completedToday;
  final int totalHabits;
  final String? longestStreakName;
  final int longestStreakDays;
}

class FocusStatistics {
  const FocusStatistics({required this.sessionsToday, required this.minutesFocusedToday, required this.currentStreakDays});

  final int sessionsToday;
  final int minutesFocusedToday;
  final int currentStreakDays;
}

/// How this specific person likes to be talked to - learned over time, not
/// configured in a settings screen. Updated by the nightly pattern job, not
/// by the live conversation turn.
class CoachUserPreferences {
  const CoachUserPreferences({
    this.prefersBrevity = false,
    this.dislikesBeingAskedHowTheyAre = false,
    this.respondsWellToHumor = false,
    this.preferredName,
  });

  final bool prefersBrevity;
  final bool dislikesBeingAskedHowTheyAre;
  final bool respondsWellToHumor;
  final String? preferredName;
}
