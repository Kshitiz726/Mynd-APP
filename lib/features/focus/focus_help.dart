import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/utils/haptics.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/coach_provider.dart';
import '../../providers/focus_provider.dart';
import '../../providers/nav_provider.dart';
import '../../providers/task_provider.dart';

/// Routes a "Need help" tap from Focus straight to Mynd (the AI coach), priming
/// it with the user's live context — what they're working on, how long they've
/// been at it, and how many alerts are tugging at their attention — and asking
/// for a gentle, consoling, motivating nudge with one tiny next step.
///
/// The coach already folds energy/tasks/focus state into its prompt; this adds
/// the focus-specific framing on top.
void askMyndForHelp(BuildContext context) {
  final nav = context.read<NavProvider>();
  final focus = context.read<FocusProvider>();
  final tasks = context.read<TaskProvider>();
  final alerts = context.read<AlertsProvider>();
  final coach = context.read<CoachProvider>();

  final task = tasks.upNext?.title ??
      (focus.isActive ? 'my current focus block' : 'my next task');

  final buf = StringBuffer()
    ..write("I just tapped 'Need help' from my Focus screen and I'm struggling. ");
  if (focus.isActive) {
    buf.write(
        "I'm in a ${focus.activeMode?.name ?? 'focus'} session with ${focus.timeString} left, "
        'working on "$task". ');
  } else {
    buf.write('I want to work on "$task" but I can\'t get myself started. ');
  }

  final alertCount = alerts.allNotifications.length;
  if (alertCount > 0) {
    buf.write('I also have $alertCount recent alerts pulling at my attention. ');
  }
  buf.write(
      'Please be gentle and consoling, hype me up a little, and give me one tiny next step I can do right now.');

  Haptics.medium();
  nav.select(AppTab.coach);
  coach.send(buf.toString());
}
