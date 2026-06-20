import 'energy_level.dart';
import 'task.dart';

/// One day's chunk of work toward a [Goal]. The breakdown spreads these across
/// the days between today and the goal's target date so the goal turns into a
/// sequence of small, dated, do-able steps instead of one scary mountain.
class GoalMilestone {
  GoalMilestone({
    required this.id,
    required this.title,
    required this.date,
    required this.energy,
    this.done = false,
    List<MicroStep>? steps,
  }) : steps = steps ?? [];

  final String id;
  final String title;

  /// The calendar day this chunk is meant to be tackled on.
  final DateTime date;

  final EnergyLevel energy;
  bool done;
  final List<MicroStep> steps;
}

/// A user goal with a deadline, broken down into a day-by-day plan of
/// [GoalMilestone]s.
class Goal {
  Goal({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.targetDate,
    required this.milestones,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime targetDate;
  final List<GoalMilestone> milestones;

  int get total => milestones.length;
  int get doneCount => milestones.where((m) => m.done).length;
  double get progress => total == 0 ? 0 : doneCount / total;
  bool get isComplete => total > 0 && doneCount == total;
}
