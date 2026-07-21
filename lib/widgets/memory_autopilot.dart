import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../features/memory/memory_actions.dart';
import '../providers/coach_provider.dart';
import '../providers/memory_provider.dart';

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
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final coach = context.watch<CoachProvider>();
    final memory = context.watch<MemoryProvider>();

    if (coach.completedTurns != _seenTurns) {
      _seenTurns = coach.completedTurns;
      memory.markDirty();
    }

    // Never mid-reply: the transcript we would snapshot is half-written, and
    // the model call would compete with the one the user is waiting on.
    if (memory.wantsRefresh && !coach.isStreaming && !_running) {
      _running = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) {
          _running = false;
          return;
        }
        await refreshMemory(context, haptic: false, quiet: true);
        _running = false;
      });
    }

    return widget.child;
  }
}
