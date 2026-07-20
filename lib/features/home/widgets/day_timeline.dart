import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/toast.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_states.dart';
import '../../../widgets/om_tappable.dart';
import '../../../models/task.dart';
import 'edit_task_sheet.dart';

/// "your day" — the time-blocked schedule.
///
/// Redesigned to match the prototype with a "NOW" indicator, vertical category
/// bars, and "Available" slots between blocks.
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    final scheduled = context.watch<TaskProvider>().daySchedule;

    if (scheduled.isEmpty) {
      return const OmEmptyState(
        message: "nothing blocked in yet — tap the calendar on a backlog task to slot it into your day.",
      );
    }

    // Gap between NOW and the first scheduled block — a fillable, locked slot.
    final now = DateTime.now();
    final firstStart = scheduled.first.startTime;
    Duration? leadingGap;
    if (firstStart != null && firstStart.isAfter(now)) {
      final diff = firstStart.difference(now);
      if (diff.inMinutes >= 5) leadingGap = diff;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _NowIndicator(),
        const SizedBox(height: AppSpacing.md),
        if (leadingGap != null) ...[
          _AvailableSlot(start: now, gap: leadingGap),
          const SizedBox(height: AppSpacing.sm),
        ],
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: scheduled.length,
          itemBuilder: (context, index) {
            final current = scheduled[index];
            Duration? gapAfter;
            DateTime? gapStart;
            if (index < scheduled.length - 1) {
              final next = scheduled[index + 1];
              if (current.endTime != null && next.startTime != null && current.endTime!.isBefore(next.startTime!)) {
                final diff = next.startTime!.difference(current.endTime!);
                if (diff.inMinutes >= 5) {
                  gapAfter = diff;
                  gapStart = current.endTime;
                }
              }
            }
            return ReorderableDragStartListener(
              key: ValueKey(current.id),
              index: index,
              child: _TimelineBlock(
                task: current,
                gapAfter: gapAfter,
                gapStart: gapStart,
              ),
            );
          },
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = scheduled.removeAt(oldIndex);
            scheduled.insert(newIndex, item);
            final settings = context.read<SettingsProvider>();
            context.read<TaskProvider>().recalculateSchedule(scheduled, settings.wakeUpTime, settings.selectedRingtone);
          },
        ),
      ],
    );
  }
}

class _NowIndicator extends StatefulWidget {
  const _NowIndicator();

  @override
  State<_NowIndicator> createState() => _NowIndicatorState();
}

class _NowIndicatorState extends State<_NowIndicator> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final nowStr = DateFormat.jm().format(DateTime.now());
    return Row(
      children: [
        SizedBox(
          width: 55,
          child: Text(nowStr, style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: c.primary,
            fontSize: 11,
          )),
        ),
        const SizedBox(width: AppSpacing.md),
        Container(width: 8, height: 8, decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
          child: Text('NOW', style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 9,
            letterSpacing: 0.8,
          )),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(height: 2, color: c.primary.withValues(alpha: 0.2))),
      ],
    );
  }
}

class _TimelineBlock extends StatelessWidget {
  const _TimelineBlock({required this.task, this.gapAfter, this.gapStart});

  final Task task;
  final Duration? gapAfter;
  final DateTime? gapStart;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final energyColor = task.energy.color(context);
    // Goal-derived blocks read in the brand accent so they stand apart from the
    // energy-coloured task blocks.
    final accent = task.isGoalTask ? c.primary : energyColor;

    final startStr = task.startTime != null ? DateFormat.jm().format(task.startTime!) : task.time.split(' ').first;
    final endStr = task.endTime != null ? DateFormat.jm().format(task.endTime!) : task.time;

    // Done blocks tint toward their accent instead of staying white — finished
    // work should read as settled at a glance, without relying on the
    // strikethrough being legible.
    final cardColor = task.done ? accent.withValues(alpha: 0.10) : c.surface;

    Widget block = Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OmTappable(
        onLongPress: () => showEditTaskSheet(context, task),
        feedback: OmTapFeedback.none,
        pressedScale: 0.99,
        onTap: null, // Just for long press right now
        child: Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: task.done ? accent.withValues(alpha: 0.18) : c.border,
            ),
            boxShadow: task.done
                ? null
                : [
                    BoxShadow(
                      color: c.shadow.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
          ),
          padding: const EdgeInsets.fromLTRB(14, 16, 16, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The check leads the card, so completing is the nearest action.
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: _CheckCircle(
                  done: task.done,
                  color: task.done ? accent : c.border.withValues(alpha: 0.9),
                  onTap: () {
                    Haptics.medium();
                    context.read<TaskProvider>().toggleDone(task);
                    if (task.isGoalTask) {
                      context.read<GoalProvider>().markMilestoneDone(task.id, task.done);
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 17,
                            height: 1.25,
                            fontWeight: FontWeight.w800,
                            color: task.done ? c.text2 : c.text,
                            decoration: task.done ? TextDecoration.lineThrough : null,
                          ),
                    ),
                    const SizedBox(height: 8),
                    // Time reads as metadata under the title, the way the
                    // reference's "1 min article" line does — still tappable.
                    OmTappable(
                      onTap: () => _editBlockTime(context, task),
                      feedback: OmTapFeedback.none,
                      pressedScale: 0.97,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(OmIcons.byName('clock'), size: 13, color: c.text2),
                          const SizedBox(width: 5),
                          Text(
                            '$startStr - $endStr',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: c.text2,
                                ),
                          ),
                          const SizedBox(width: 8),
                          // Energy / goal provenance, demoted to a quiet dot-tag.
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              task.isGoalTask
                                  ? (task.goalTitle ?? 'goal')
                                  : task.isChunk
                                      ? '${task.energy.label} · part ${task.chunkIndex}/${task.chunkCount}'
                                      : task.energy.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: accent,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (gapAfter != null && gapStart != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          block,
          _AvailableSlot(start: gapStart!, gap: gapAfter!),
        ],
      );
    }

    return block;
  }
}

/// Lets the user re-time a block: pick a new start, then a new end. Validates
/// that end follows start (treats an earlier end as crossing midnight).
Future<void> _editBlockTime(BuildContext context, Task task) async {
  final base = task.startTime ?? DateTime.now();
  final start = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(base),
    helpText: 'Start time',
  );
  if (start == null || !context.mounted) return;

  final endBase = task.endTime ?? base.add(const Duration(hours: 1));
  final end = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(endBase),
    helpText: 'End time',
  );
  if (end == null || !context.mounted) return;

  var s = DateTime(base.year, base.month, base.day, start.hour, start.minute);
  var e = DateTime(base.year, base.month, base.day, end.hour, end.minute);
  if (!e.isAfter(s)) e = e.add(const Duration(days: 1)); // crosses midnight

  final tasks = context.read<TaskProvider>();
  // Only let a block move into a genuinely free slot — otherwise tell the user
  // exactly what it would collide with instead of silently double-booking.
  final clash = tasks.conflictFor(task, s, e);
  if (clash != null) {
    Haptics.medium();
    final cs = clash.startTime != null ? DateFormat.jm().format(clash.startTime!) : '';
    final ce = clash.endTime != null ? DateFormat.jm().format(clash.endTime!) : '';
    Toast.show(context, 'That overlaps "${clash.title}" ($cs–$ce). Pick a free slot.');
    return;
  }

  final settings = context.read<SettingsProvider>();
  tasks.setTaskTime(task, s, e, ringtone: settings.selectedRingtone);
  Haptics.success();
}

/// A locked "Available" gap in the timeline. The slot itself can't be dragged
/// (only task blocks move); tapping it opens the backlog so the user can drop a
/// task straight into the gap, trimmed to fit.
class _AvailableSlot extends StatelessWidget {
  const _AvailableSlot({required this.start, required this.gap});

  final DateTime start;
  final Duration gap;

  String get _durationStr {
    final h = gap.inHours;
    final m = gap.inMinutes % 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        children: [
          SizedBox(
            width: 55,
            child: Text(
              DateFormat.jm().format(start),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: c.text2,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Expanded(
            child: OmTappable(
              onTap: () => _showFillSheet(context, start, gap),
              feedback: OmTapFeedback.light,
              pressedScale: 0.98,
              child: DottedSlot(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(OmIcons.byName('plus'), size: 14, color: c.primary),
                      const SizedBox(width: 6),
                      Text('Free • $_durationStr',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: c.primary,
                                fontWeight: FontWeight.w600,
                              )),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft dashed-border container used for empty/available slots.
class DottedSlot extends StatelessWidget {
  const DottedSlot({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.05),
        border: Border.all(color: c.primary.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}

/// Bottom sheet that lists backlog tasks to drop into a tapped gap.
Future<void> _showFillSheet(BuildContext context, DateTime start, Duration gap) async {
  final tasks = context.read<TaskProvider>();
  final settings = context.read<SettingsProvider>();
  final items = tasks.backlog;

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final c = sheetContext.omColors;
      final h = gap.inHours;
      final m = gap.inMinutes % 60;
      final gapStr = h > 0 ? '${h}h ${m}m' : '${m}m';
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('fill this slot', style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('${DateFormat.jm().format(start)} · $gapStr free — pick something to slot in.',
                  style: Theme.of(sheetContext).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.lg),
              if (items.isEmpty)
                const OmEmptyState(message: 'nothing in the backlog to slot in right now.')
              else
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, i) {
                      final t = items[i];
                      final color = t.isGoalTask ? c.primary : t.energy.color(sheetContext);
                      return OmTappable(
                        onTap: () {
                          Haptics.success();
                          tasks.fillSlot(t, start, gap, ringtone: settings.selectedRingtone);
                          Navigator.of(sheetContext).pop();
                        },
                        pressedScale: 0.98,
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(AppRadius.control),
                            border: Border.all(color: color.withValues(alpha: 0.22)),
                          ),
                          child: Row(
                            children: [
                              Icon(t.isGoalTask ? OmIcons.byName('activity') : t.energy.icon,
                                  size: 18, color: color),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Text(t.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(sheetContext).textTheme.bodyLarge?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        )),
                              ),
                              Icon(OmIcons.byName('chevR'), size: 16, color: color.withValues(alpha: 0.6)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _CheckCircle extends StatelessWidget {
  const _CheckCircle({required this.done, required this.color, required this.onTap});

  final bool done;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
        ),
        child: done ? Icon(OmIcons.byName('check'), size: 14, color: color) : null,
      ),
    );
  }
}
