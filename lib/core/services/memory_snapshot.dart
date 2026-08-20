import 'package:intl/intl.dart';

import '../../providers/community_provider.dart';
import '../../providers/energy_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/mood_provider.dart';
import '../../providers/task_provider.dart';
import 'coach_memory_service.dart';

/// Flattens everything the app has seen into the plain-text brief the memory
/// model is asked to write from.
///
/// It is deliberately terse and factual - counts, titles, times. The model does
/// the interpreting; if this file starts editorialising, two different voices
/// end up in the profile.
String buildMemorySnapshot({
  required String userName,
  required TaskProvider tasks,
  required GoalProvider goals,
  required HabitProvider habits,
  required EnergyProvider energy,
  required CommunityProvider community,
  MoodProvider? mood,
  String recentChat = '',
}) {
  final b = StringBuffer();
  final fmt = DateFormat.jm();

  b.writeln('Name: $userName');
  b.writeln('Right now they report their energy as: ${energy.current.label}');

  // ── The day as planned ──
  final today = tasks.todaySchedule.where((t) => !t.isAnchor).toList();
  if (today.isEmpty) {
    b.writeln('Today: nothing time-blocked.');
  } else {
    b.writeln('Today they blocked out ${today.length} things:');
    for (final t in today.take(10)) {
      final when = t.startTime != null ? fmt.format(t.startTime!) : 'unscheduled';
      b.writeln('- ${t.title} at $when (${t.energy.label} energy)${t.done ? ' [done]' : ''}');
    }
  }

  // ── What keeps not happening ──
  final backlog = tasks.backlog;
  if (backlog.isNotEmpty) {
    b.writeln('Sitting in their backlog, unscheduled (${backlog.length}):');
    for (final t in backlog.take(10)) {
      b.writeln('- ${t.title} (${t.energy.label} energy)');
    }
  }

  // ── Goals and how the plan is actually going ──
  if (goals.goals.isEmpty) {
    b.writeln('Goals: none set.');
  } else {
    b.writeln('Goals:');
    for (final g in goals.goals) {
      final pct = (g.progress * 100).round();
      b.writeln('- "${g.title}", due ${DateFormat.yMMMd().format(g.targetDate)}, '
          '$pct% of its daily steps done (${g.doneCount}/${g.total})');
      final next = g.milestones.where((m) => !m.done).take(2);
      for (final m in next) {
        b.writeln('  next step: ${m.title}');
      }
    }
    final drift = goals.overallProgress - goals.expectedProgress;
    if (drift < -0.15) {
      b.writeln('They are behind where the plan expected them to be by now.');
    } else if (drift > 0.10) {
      b.writeln('They are ahead of where the plan expected them to be.');
    }
  }

  // ── Habits ──
  var habitTotal = 0, habitDone = 0;
  final habitNames = <String>[];
  for (final board in habits.boards) {
    for (final h in board.items) {
      habitTotal++;
      if (h.done) habitDone++;
      if (habitNames.length < 8) habitNames.add(h.name);
    }
  }
  if (habitTotal > 0) {
    b.writeln('Habits they track: ${habitNames.join(', ')} '
        '($habitDone of $habitTotal ticked today).');
  }

  // ── How the days have actually felt ──
  if (mood != null) {
    final today = mood.today;
    if (today != null) b.writeln('Today they logged their mood as: ${today.mood.label}.');
    final logged = mood.recent.whereType<MoodEntry>().toList();
    if (logged.length >= 3) {
      final trail = logged.map((e) => e.mood.label).join(' → ');
      b.writeln('Their last logged moods, oldest first: $trail.');
    }
  }

  // ── What they engage with in the community ──
  //
  // Who someone chooses to show up for says as much as their task list does,
  // so reactions and their own posts both count.
  final mine = community.posts.where((p) => p.myReactions.isNotEmpty).toList();
  if (mine.isNotEmpty) {
    b.writeln('Posts they reacted to:');
    for (final p in mine.take(6)) {
      final body = p.body.length > 90 ? '${p.body.substring(0, 90)}…' : p.body;
      b.writeln('- "$body"${p.tags.isEmpty ? '' : ' [${p.tags.join(', ')}]'}');
    }
  }

  // ── What the coach already learned ──
  final coachMemo = CoachMemoryService.instance.memorySummary;
  if (coachMemo.isNotEmpty) {
    b.writeln('From their coaching conversations:\n$coachMemo');
  }

  // ── What they said most recently, verbatim ──
  //
  // The rolling memo above is compressed and a little lossy; the last few
  // exchanges are where anything new and still raw actually lives.
  if (recentChat.isNotEmpty) {
    b.writeln('Their most recent exchange with the coach:\n$recentChat');
  }

  return b.toString().trim();
}
