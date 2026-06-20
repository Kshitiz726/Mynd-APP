import 'dart:ui';

/// How a habit is completed.
enum HabitKind {
  /// Tap once to mark done.
  simple,

  /// Launches a focus timer for [Habit.minutes] minutes.
  timer,
}

/// A single habit tile (e.g. "hydrate", "deep work").
///
/// Deliberately *gentle*: there are no streaks to break, in line with the
/// prototype's "habit tracker — gentle, no streaks to break." philosophy.
class Habit {
  Habit({
    required this.id,
    required this.iconName,
    required this.name,
    required this.color,
    this.kind = HabitKind.simple,
    this.minutes,
    this.done = false,
  });

  final String id;
  final String iconName;
  final String name;

  /// Per-habit accent color (mirrors the prototype's `--hcolor`).
  final Color color;

  final HabitKind kind;

  /// Duration in minutes when [kind] is [HabitKind.timer].
  final int? minutes;

  bool done;
}

/// A named page of habits ("Morning", "Focus", "Evening") shown as a
/// snap-scrolling carousel with tab indicators.
class HabitBoard {
  HabitBoard({required this.id, required this.name, required this.items});

  final String id;
  final String name;
  final List<Habit> items;
}
