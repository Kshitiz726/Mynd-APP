import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/memory/memory_actions.dart';
import '../providers/coach_provider.dart';
import '../providers/goal_provider.dart';
import '../providers/habit_provider.dart';
import '../providers/memory_provider.dart';
import '../providers/mood_provider.dart';
import '../providers/task_provider.dart';

/// Keeps "what OurMynd knows about you" current without anybody pressing
/// anything.
///
/// The memory used to be rewritten in two places: a refresh button on the card,
/// and a once-a-day pass that only fired if you happened to open Home. So a
/// long conversation with the coach on Tuesday evening could reach the profile
/// on Thursday, or never. Asking the user to press refresh on their own memory
/// is asking them to do the app's filing.
///
/// This sits in the shell, where it is mounted for the whole signed-in session,
/// and rewrites the memory when there is actually something new to fold in: a
/// finished exchange with the coach, a parked thought, or a day going by.
/// [MemoryProvider.wantsRefresh] holds the cooldown, so a twenty message
/// conversation costs one or two model calls, not twenty.
class MemoryAutopilot extends StatefulWidget {
  const MemoryAutopilot({super.key, required this.child});

  final Widget child;

  @override
  State<MemoryAutopilot> createState() => _MemoryAutopilotState();
}

class _MemoryAutopilotState extends State<MemoryAutopilot> {
  int _seenTurns = 0;
  String? _seenStamp;
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final memory = context.watch<MemoryProvider>();
    final mood = context.watch<MoodProvider>();
    final tasks = context.watch<TaskProvider>();
    final goals = context.watch<GoalProvider>();
    final habits = context.watch<HabitProvider>();

    if (coach.completedTurns != _seenTurns) {
      _seenTurns = coach.completedTurns;
      memory.markDirty();
    }

    // Anything else the user actually did. Finishing a task, adding a goal,
    // keeping a habit and logging a mood all change who the profile is about,
    // and none of them used to count: the memory only listened to the coach,
    // so a week of real work could go in and the profile would still be
    // describing the last conversation.
    //
    // A stamp of counts rather than deep equality. It is compared on every
    // build, so it has to be cheap, and it only has to be right about "has
    // something happened" - the cooldown decides whether that is worth a call,
    // and getting the answer a few minutes late costs nothing.
    final stamp = '${tasks.all.length}/${tasks.doneCount}'
        '·${goals.goals.length}/${goals.activeCount}'
        '·${habits.boards.length}'
        '·${mood.entries.length}/${mood.today?.mood.name ?? '-'}';
    if (_seenStamp != stamp) {
      final first = _seenStamp == null;
      _seenStamp = stamp;
      // The first build is not a change, it is just the app finding out what
      // is already there.
      if (!first) memory.markDirty();
    }

    // Never mid-reply: the transcript we would snapshot is half-written, and
    // the model call would compete with the one the user is waiting on.
    if (!coach.isStreaming && !_running) {
      // Memory first, and the mood only once it is settled - the reading is
      // given the profile as input, so doing them the other way round reads
      // yesterday's picture of the user and then immediately replaces it.
      final Future<void> Function(BuildContext)? job = memory.wantsRefresh
          ? (ctx) => refreshMemory(ctx, haptic: false, quiet: true)
          : (mood.wantsReading ? readMood : null);
      if (job != null) {
        _running = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) {
            _running = false;
            return;
          }
          await job(context);
          _running = false;
        });
      }
    }

    return widget.child;
  }
}
