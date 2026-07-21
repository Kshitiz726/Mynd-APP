import 'package:flutter/material.dart' show TimeOfDay;

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

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'date': date.toIso8601String(),
        'energy': energy.name,
        'done': done,
        if (steps.isNotEmpty) 'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory GoalMilestone.fromJson(Map<String, dynamic> j) => GoalMilestone(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        date: DateTime.parse(j['date'] as String),
        energy: EnergyLevel.values.firstWhere(
          (e) => e.name == j['energy'],
          orElse: () => EnergyLevel.low,
        ),
        done: j['done'] as bool? ?? false,
        steps: (j['steps'] as List?)
            ?.map((s) => MicroStep.fromJson((s as Map).cast<String, dynamic>()))
            .toList(),
      );
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
    this.dailyStart,
    this.dailyMinutes = 60,
  });

  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime targetDate;
  final List<GoalMilestone> milestones;

  /// The time of day the user set aside for this goal, chosen when the goal was
  /// created. Today's step lands here on the timeline instead of wherever
  /// auto-schedule happened to have room, because a goal you have not booked
  /// time for is a wish.
  final TimeOfDay? dailyStart;

  /// How long they committed to it each day.
  final int dailyMinutes;

  Duration get dailyDuration => Duration(minutes: dailyMinutes);

  /// [dailyStart] resolved onto [day], or null when no slot was chosen.
  DateTime? slotOn(DateTime day) {
    final s = dailyStart;
    if (s == null) return null;
    return DateTime(day.year, day.month, day.day, s.hour, s.minute);
  }

  int get total => milestones.length;
  int get doneCount => milestones.where((m) => m.done).length;
  double get progress => total == 0 ? 0 : doneCount / total;
  bool get isComplete => total > 0 && doneCount == total;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
        'targetDate': targetDate.toIso8601String(),
        'milestones': milestones.map((m) => m.toJson()).toList(),
        if (dailyStart != null) 'dailyStart': dailyStart!.hour * 60 + dailyStart!.minute,
        'dailyMinutes': dailyMinutes,
      };

  factory Goal.fromJson(Map<String, dynamic> j) {
    final slot = j['dailyStart'] as int?;
    return Goal(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      createdAt: DateTime.parse(j['createdAt'] as String),
      targetDate: DateTime.parse(j['targetDate'] as String),
      milestones: (j['milestones'] as List? ?? [])
          .map((m) => GoalMilestone.fromJson((m as Map).cast<String, dynamic>()))
          .toList(),
      dailyStart: slot == null ? null : TimeOfDay(hour: slot ~/ 60, minute: slot % 60),
      dailyMinutes: j['dailyMinutes'] as int? ?? 60,
    );
  }
}
