import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/toast.dart';
import '../../../models/task.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_tappable.dart';
import 'edit_task_sheet.dart';

/// A backlog task row with a checkbox, energy tag, schedule button, and an
/// expandable list of micro-steps. Mirrors the prototype's `.task` element.
class TaskTile extends StatelessWidget {
  const TaskTile({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.read<TaskProvider>();
    final energyColor = task.energy.color(context);

    // Swipe right to throw it away.
    //
    // The backlog is where things go to be avoided, and a list you cannot prune
    // stops being a list of what you might do and becomes a monument to what
    // you did not. Deleting was previously buried in the long-press edit sheet,
    // which nobody finds. One direction only: swiping left is how the timeline
    // sends a block back here, and the two gestures meaning opposite things on
    // the same row would be a trap.
    return Dismissible(
      key: ValueKey('backlog-${task.id}'),
      direction: DismissDirection.startToEnd,
      // A slow drag reveals the intent before it commits, and it takes a real
      // swipe (not a twitch) to actually delete.
      dismissThresholds: const {DismissDirection.startToEnd: 0.45},
      background: _DeleteBackground(),
      onDismissed: (_) {
        Haptics.medium();
        tasks.deleteTask(task.id);
        // Nothing here is worth losing to a mis-swipe.
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(
            content: Text('deleted "${task.title}"'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'undo',
              onPressed: () => tasks.addTasks([task]),
            ),
          ));
      },
      child: _tile(context, c, tasks, energyColor),
    );
  }

  Widget _tile(BuildContext context, OmColors c, TaskProvider tasks, Color energyColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.control),
        child: Stack(
          children: [
            // The vertical energy bar
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(width: 5, color: energyColor),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                OmTappable(
                  onLongPress: () => showEditTaskSheet(context, task),
                  feedback: OmTapFeedback.light,
                  pressedScale: 0.985,
                  onTap: () {
                    if (!task.hasSteps) {
                      Toast.show(context, 'no breakdown yet - dump it again with + to auto-split it.');
                      return;
                    }
                    tasks.toggleExpanded(task);
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(21, 16, 16, 16), // Extra left padding for bar
                    child: Row(
                      children: [
                        _Check(
                          done: task.done,
                          color: c.success,
                          border: c.border.withValues(alpha: 0.8),
                          onTap: () {
                            Haptics.medium();
                            tasks.toggleDone(task);
                          },
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                task.title,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      decoration: task.done ? TextDecoration.lineThrough : null,
                                      color: task.done ? c.text2 : c.text,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(task.time, style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  )),
                                  if (task.hasSteps) ...[
                                    const SizedBox(width: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: c.primaryTint,
                                        borderRadius: BorderRadius.circular(AppRadius.pill),
                                      ),
                                      child: Text(
                                        '${task.stepCount} steps',
                                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: c.primary,
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        if (!task.scheduled)
                          IconButton(
                            tooltip: 'Schedule block',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: Icon(OmIcons.byName('calendar'), size: 18, color: c.text2),
                            onPressed: () {
                              Haptics.select();
                              tasks.schedule(task);
                              final label = tasks.viewingToday
                                  ? 'your day'
                                  : DateFormat.MMMEd().format(tasks.selectedDate);
                              Toast.show(context, 'added to $label');
                            },
                          ),
                        const SizedBox(width: AppSpacing.md),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: energyColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(task.energy.icon, size: 15, color: energyColor),
                        ),
                      ],
                    ),
                  ),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                  child: task.expanded && task.hasSteps
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(21, 0, 16, 12),
                          child: Column(
                            children: [
                              for (final (i, step) in task.steps.indexed)
                                _StepRow(index: i + 1, step: step, onTap: () {
                                  Haptics.light();
                                  tasks.toggleStep(task, step);
                                }),
                            ],
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Check extends StatelessWidget {
  const _Check({required this.done, required this.color, required this.border, required this.onTap});

  final bool done;
  final Color color;
  final Color border;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: done ? color : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(color: done ? color : border, width: 2),
          boxShadow: done
              ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 3))]
              : null,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 320),
          transitionBuilder: (child, anim) => ScaleTransition(
            scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
            child: child,
          ),
          child: done
              ? Icon(OmIcons.byName('check'),
                  key: const ValueKey('done'), size: 15, color: Colors.white)
              : const SizedBox.shrink(key: ValueKey('empty')),
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.index, required this.step, required this.onTap});

  final int index;
  final MicroStep step;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: step.done ? c.success : c.surfaceAlt,
                shape: BoxShape.circle,
              ),
              child: step.done
                  ? Icon(OmIcons.byName('check'), size: 12, color: Colors.white)
                  : Text('$index', style: Theme.of(context).textTheme.labelSmall),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                step.text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: step.done ? c.text2 : c.text,
                      decoration: step.done ? TextDecoration.lineThrough : null,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What sits behind a backlog row while you drag it aside.
///
/// Grows into a full red panel rather than appearing at the threshold, so the
/// gesture reads as "this is what happens if you keep going" the whole way.
class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: c.error,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(OmIcons.byName('trash'), size: 19, color: Colors.white),
          const SizedBox(width: 10),
          const Text('delete',
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
        ],
      ),
    );
  }
}
