import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/task_icon.dart';
import '../../../core/utils/toast.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_states.dart';
import '../../../widgets/om_tappable.dart';
import '../../../models/energy_level.dart';
import '../../../models/task.dart';
import 'edit_task_sheet.dart';

/// "your day" - the time-blocked schedule.
///
/// Redesigned to match the prototype with a "NOW" indicator, vertical category
/// bars, and "Available" slots between blocks.
class DayTimeline extends StatelessWidget {
  const DayTimeline({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TaskProvider>();
    final day = tasks.selectedDate;

    // A past day is a record of what happened, not something to re-plan.
    if (!tasks.canPlan(day)) return _PastDay(day: day);

    final scheduled = tasks.daySchedule;

    if (scheduled.isEmpty) {
      return const OmEmptyState(
        message: "nothing blocked in yet - tap the calendar on a backlog task to slot it into your day.",
      );
    }

    // Wake and sleep are fixed points, so they are pulled out of the reorderable
    // list entirely: a block cannot be dropped above waking or below bedtime,
    // and no drag can shift their times.
    final wake = scheduled.where((t) => t.id == 'wake_anchor').firstOrNull;
    final sleep = scheduled.where((t) => t.id == 'sleep_anchor').firstOrNull;
    final movable = scheduled.where((t) => !t.isAnchor).toList();

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
        if (tasks.viewingToday) ...[
          const _NowIndicator(),
          const SizedBox(height: AppSpacing.md),
        ],
        if (leadingGap != null) ...[
          _AvailableSlot(start: now, gap: leadingGap),
          const SizedBox(height: AppSpacing.sm),
        ],
        if (wake != null) _TimelineBlock(task: wake, pinned: true),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: movable.length,
          itemBuilder: (context, index) {
            final current = movable[index];
            Duration? gapAfter;
            DateTime? gapStart;
            if (index < movable.length - 1) {
              final next = movable[index + 1];
              if (current.endTime != null && next.startTime != null && current.endTime!.isBefore(next.startTime!)) {
                final diff = next.startTime!.difference(current.endTime!);
                if (diff.inMinutes >= 5) {
                  gapAfter = diff;
                  gapStart = current.endTime;
                }
              }
            }
            // Delayed, not immediate: an immediate listener swallowed vertical
            // drags, so scrolling the page picked a block up instead.
            return ReorderableDelayedDragStartListener(
              key: ValueKey(current.id),
              index: index,
              child: _TimelineBlock(
                task: current,
                gapAfter: gapAfter,
                gapStart: gapStart,
                isLast: sleep == null && index == movable.length - 1,
              ),
            );
          },
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = movable.removeAt(oldIndex);
            movable.insert(newIndex, item);
            Haptics.medium();

            final settings = context.read<SettingsProvider>();
            // Repack strictly between the anchors: after the wake block ends,
            // and finishing before wind-down begins.
            final windowStart = wake?.endTime ??
                DateTime(day.year, day.month, day.day,
                    settings.wakeUpTime.hour, settings.wakeUpTime.minute);
            final windowEnd = sleep?.startTime ??
                DateTime(day.year, day.month, day.day,
                    settings.sleepTime.hour, settings.sleepTime.minute);
            context.read<TaskProvider>().recalculateSchedule(
                  movable,
                  windowStart,
                  windowEnd,
                  settings.selectedRingtone,
                );
          },
        ),
        if (sleep != null) _TimelineBlock(task: sleep, pinned: true, isLast: true),
      ],
    );
  }
}

/// Soft card tints, cycled by task id so a block keeps its colour.
const _blockTints = [
  Color(0xFFF3F0FF), // lavender
  Color(0xFFFFF1E8), // peach
  Color(0xFFEAF7EF), // mint
  Color(0xFFFFF6DC), // butter
  Color(0xFFEAF2FF), // sky
  Color(0xFFFDECF2), // blush
];

Color _blockTint(Task task, BuildContext context) {
  final c = context.omColors;
  // Done blocks drop out of the palette: finished work should recede.
  if (task.done) return c.surfaceAlt;
  if (context.isDark) return c.surfaceAlt;
  return _blockTints[task.id.hashCode.abs() % _blockTints.length];
}

/// The dashed thread joining one block to the next.
class _DashedRail extends StatelessWidget {
  const _DashedRail({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _DashedRailPainter(color), size: const Size(2, double.infinity));
}

class _DashedRailPainter extends CustomPainter {
  const _DashedRailPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    const dash = 4.0, gap = 5.0;
    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(size.width / 2, y), Offset(size.width / 2, (y + dash).clamp(0, size.height)), paint);
      y += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_DashedRailPainter old) => old.color != color;
}

/// A finished day: what actually happened, with no way to edit it.
class _PastDay extends StatelessWidget {
  const _PastDay({required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final stats = tasks.statsFor(day);
    final done = tasks.doneOn(day).where((t) => !t.isAnchor).toList();

    final hours = stats.focused.inMinutes / 60;
    final focusedLabel = stats.focused.inMinutes < 60
        ? '${stats.focused.inMinutes}m'
        : '${hours.toStringAsFixed(hours.truncateToDouble() == hours ? 0 : 1)}h';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE, MMM d').format(day).toLowerCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.text2),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _Stat(value: '${stats.done}', label: 'done', color: c.primary),
                  _Stat(value: focusedLabel, label: 'focused', color: c.primary),
                  _Stat(value: '${stats.missed}', label: 'missed', color: c.text2),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        if (done.isEmpty)
          const OmEmptyState(message: "nothing was ticked off that day. that is allowed.")
        else
          for (var i = 0; i < done.length; i++)
            _TimelineBlock(task: done[i], pinned: true, isLast: i == done.length - 1),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});

  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2),
          ),
        ],
      ),
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
  const _TimelineBlock({
    required this.task,
    this.gapAfter,
    this.gapStart,
    this.pinned = false,
    this.isLast = false,
  });

  final Task task;
  final Duration? gapAfter;
  final DateTime? gapStart;

  /// Fixed blocks (wake, sleep, and everything on a past day): no editing, no
  /// dragging, and visually quieter so they read as the frame of the day.
  final bool pinned;

  /// The thread stops at the last block; trailing off into empty space reads as
  /// an unfinished list.
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final energyColor = task.energy.color(context);
    // Goal-derived blocks read in the brand accent so they stand apart from the
    // energy-coloured task blocks.
    final accent = task.isGoalTask ? c.primary : energyColor;

    final startStr = task.startTime != null ? DateFormat.jm().format(task.startTime!) : task.time.split(' ').first;
    final endStr = task.endTime != null ? DateFormat.jm().format(task.endTime!) : task.time;

    // Each block takes a soft tint from a fixed palette, keyed off its id, so a
    // task keeps its colour between rebuilds and the day reads as a sequence of
    // distinct things rather than a wall of white cards.
    final tint = _blockTint(task, context);

    Widget block = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The rail: a check per block, joined by a dashed line so the day
          // reads as one continuous thread.
          SizedBox(
            width: 34,
            child: Column(
              children: [
                const SizedBox(height: 18),
                pinned && !task.done
                    ? Container(
                        width: 24,
                        height: 24,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(taskIcon(task.title), size: 13, color: accent),
                      )
                    : _CheckCircle(
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
                const SizedBox(height: 6),
                if (!isLast) Expanded(child: _DashedRail(color: c.border)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: OmTappable(
                // Long-press belongs to the drag gesture, so editing is a tap.
                onLongPress: null,
                feedback: OmTapFeedback.none,
                pressedScale: pinned ? 1.0 : 0.99,
                onTap: pinned ? null : () => showEditTaskSheet(context, task),
                child: Container(
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
                  child: Row(
                    children: [
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
                            OmTappable(
                              onTap: pinned ? null : () => _showTimeSheet(context, task),
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
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // The glyph sits opposite the title, the way the reference
                      // puts an illustration on the right of every card.
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(taskIcon(task.title), size: 22, color: accent),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
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

    // Two blocks that touch have no gap to tap, so the seam between them is the
    // way in: it inserts at this block's end and pushes the rest down.
    if (!pinned && !isLast && task.endTime != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [block, _InsertSeam(at: task.endTime!)],
      );
    }

    return block;
  }
}

/// The day's editable window: after waking, before wind-down. Everything the
/// ripple does is clamped to it, so no edit can push work into the night or
/// back before the user is up.
({DateTime start, DateTime end}) _dayWindow(BuildContext context, DateTime day) {
  final tasks = context.read<TaskProvider>();
  final settings = context.read<SettingsProvider>();
  final schedule = tasks.scheduleOn(day);
  final wake = schedule.where((t) => t.id == 'wake_anchor').firstOrNull;
  final sleep = schedule.where((t) => t.id == 'sleep_anchor').firstOrNull;
  return (
    start: wake?.endTime ??
        DateTime(day.year, day.month, day.day, settings.wakeUpTime.hour, settings.wakeUpTime.minute),
    end: sleep?.startTime ??
        DateTime(day.year, day.month, day.day, settings.sleepTime.hour, settings.sleepTime.minute),
  );
}

/// Says how far past bedtime the day now runs, when a ripple pushed it there.
void _reportOverrun(BuildContext context, Duration overrun) {
  if (overrun == Duration.zero) {
    Haptics.success();
    return;
  }
  Haptics.medium();
  final h = overrun.inHours;
  final m = overrun.inMinutes % 60;
  final label = h > 0 ? '${h}h ${m}m' : '${m}m';
  Toast.show(context, 'Moved. Your day now runs $label past wind-down.');
}

/// Lets the user re-time a block: pick a new start, then a new end. Validates
/// that end follows start (treats an earlier end as crossing midnight).
///
/// Nothing is rejected for overlapping any more - the rest of the day moves out
/// of the way instead. See [TaskProvider.rippleTaskTime].
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

  final window = _dayWindow(context, base);
  final overrun = context.read<TaskProvider>().rippleTaskTime(
        task,
        s,
        e,
        window.start,
        window.end,
        ringtone: context.read<SettingsProvider>().selectedRingtone,
      );
  if (context.mounted) _reportOverrun(context, overrun);
}

/// Nudge a block earlier or later by [delta], carrying the rest of the day with
/// it. This is the fast path: no dialog, just a tap and the day re-flows.
void _nudgeBlock(BuildContext context, Task task, Duration delta) {
  final s = task.startTime;
  if (s == null) return;
  final window = _dayWindow(context, s);
  final newStart = s.add(delta);
  if (newStart.isBefore(window.start)) {
    Haptics.medium();
    Toast.show(context, "That is before you're up.");
    return;
  }
  final overrun = context.read<TaskProvider>().rippleTaskTime(
        task,
        newStart,
        newStart.add(task.duration ?? const Duration(hours: 1)),
        window.start,
        window.end,
        ringtone: context.read<SettingsProvider>().selectedRingtone,
      );
  _reportOverrun(context, overrun);
}

/// Grow or shrink a block by [delta], keeping its start where it is. Later
/// blocks slide to make room (or close the gap).
void _resizeBlock(BuildContext context, Task task, Duration delta) {
  final s = task.startTime;
  if (s == null) return;
  var dur = (task.duration ?? const Duration(hours: 1)) + delta;
  if (dur < const Duration(minutes: 5)) dur = const Duration(minutes: 5);
  final window = _dayWindow(context, s);
  final overrun = context.read<TaskProvider>().rippleTaskTime(
        task,
        s,
        s.add(dur),
        window.start,
        window.end,
        ringtone: context.read<SettingsProvider>().selectedRingtone,
      );
  _reportOverrun(context, overrun);
}

/// The block's time controls, in one sheet: nudge the whole thing earlier or
/// later, make it longer or shorter, or pick exact times. Every control ripples
/// the rest of the day, and the sheet re-reads the provider after each tap so
/// the numbers you are looking at are the numbers that are stored.
Future<void> _showTimeSheet(BuildContext context, Task task) async {
  final tasks = context.read<TaskProvider>();
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: tasks,
      child: _TimeSheet(task: task),
    ),
  );
}

class _TimeSheet extends StatelessWidget {
  const _TimeSheet({required this.task});

  final Task task;

  static const _step = Duration(minutes: 15);

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // Watch, so every nudge redraws the times from the provider itself.
    context.watch<TaskProvider>();
    final start = task.startTime;
    final end = task.endTime;
    final dur = task.duration ?? const Duration(hours: 1);
    final h = dur.inHours;
    final m = dur.inMinutes % 60;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(task.title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              start != null && end != null
                  ? '${DateFormat.jm().format(start)} - ${DateFormat.jm().format(end)}'
                  : 'not on the timeline yet',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            _StepperRow(
              label: 'move it',
              value: start != null ? DateFormat.jm().format(start) : '-',
              onMinus: () => _nudgeBlock(context, task, -_step),
              onPlus: () => _nudgeBlock(context, task, _step),
            ),
            const SizedBox(height: AppSpacing.sm),
            _StepperRow(
              label: 'how long',
              value: h > 0 ? '${h}h ${m}m' : '${m}m',
              onMinus: () => _resizeBlock(context, task, -_step),
              onPlus: () => _resizeBlock(context, task, _step),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Everything after this block shifts to keep the day continuous.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2),
            ),
            const SizedBox(height: AppSpacing.lg),
            OmTappable(
              onTap: () async {
                Navigator.of(context).pop();
                await _editBlockTime(context, task);
              },
              pressedScale: 0.98,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text('pick exact times',
                    style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A "- value +" row. Big targets, because this gets tapped repeatedly.
class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2)),
                const SizedBox(height: 2),
                Text(value,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17)),
              ],
            ),
          ),
          _StepButton(icon: Icons.remove_rounded, onTap: onMinus),
          const SizedBox(width: 8),
          _StepButton(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.88,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
        child: Icon(icon, size: 20, color: c.primary),
      ),
    );
  }
}

/// The seam between two touching blocks: tap it to slide your own task in and
/// push the rest of the day down. Auto-scheduling gives you a shape for the
/// day; this is how you put your own thing inside it.
class _InsertSeam extends StatelessWidget {
  const _InsertSeam({required this.at});

  final DateTime at;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(left: 34, bottom: AppSpacing.sm),
      child: OmTappable(
        onTap: () => _showNewBlockSheet(context, at: at),
        feedback: OmTapFeedback.light,
        pressedScale: 0.97,
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(OmIcons.byName('plus'), size: 13, color: c.primary),
            ),
            const SizedBox(width: 8),
            Text(
              'add something here',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Write a task and drop it into the day at [at]. When [maxDuration] is given
/// (a tapped Free slot) the default length is trimmed to the gap; otherwise the
/// block is inserted and everything after it moves down.
Future<void> _showNewBlockSheet(
  BuildContext context, {
  required DateTime at,
  Duration? maxDuration,
}) async {
  final tasks = context.read<TaskProvider>();
  final settings = context.read<SettingsProvider>();
  final window = _dayWindow(context, at);

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: _NewBlockSheet(
        at: at,
        maxDuration: maxDuration,
        onCreate: (title, energy, duration) {
          final task = Task(
            id: 'task-${DateTime.now().microsecondsSinceEpoch}',
            title: title,
            time: DateFormat.jm().format(at),
            energy: energy,
            duration: duration,
          );
          final overrun = tasks.insertTaskAt(
            task,
            at,
            duration,
            window.start,
            window.end,
            ringtone: settings.selectedRingtone,
          );
          Navigator.of(sheetContext).pop();
          _reportOverrun(context, overrun);
        },
      ),
    ),
  );
}

class _NewBlockSheet extends StatefulWidget {
  const _NewBlockSheet({required this.at, required this.onCreate, this.maxDuration});

  final DateTime at;
  final Duration? maxDuration;
  final void Function(String title, EnergyLevel energy, Duration duration) onCreate;

  @override
  State<_NewBlockSheet> createState() => _NewBlockSheetState();
}

class _NewBlockSheetState extends State<_NewBlockSheet> {
  final _ctrl = TextEditingController();
  EnergyLevel _energy = EnergyLevel.high;
  late int _minutes = _initialMinutes;

  static const _options = [15, 30, 45, 60, 90, 120];

  int get _initialMinutes {
    final cap = widget.maxDuration?.inMinutes;
    if (cap == null) return 30;
    return _options.lastWhere((m) => m <= cap, orElse: () => 15);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final can = _ctrl.text.trim().isNotEmpty;
    final ends = widget.at.add(Duration(minutes: _minutes));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('add your own block', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${DateFormat.jm().format(widget.at)} - ${DateFormat.jm().format(ends)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.control),
              ),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  hintText: 'What are you doing?',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('how long', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _options)
                  ChoiceChip(
                    selected: _minutes == m,
                    label: Text(m >= 60 ? '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}' : '${m}m'),
                    onSelected: (_) => setState(() => _minutes = m),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text('energy it needs', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              children: [
                for (final e in EnergyLevel.values)
                  ChoiceChip(
                    selected: _energy == e,
                    avatar: Icon(e.icon, size: 16, color: e.color(context)),
                    label: Text(e.label.toLowerCase()),
                    onSelected: (_) => setState(() => _energy = e),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: can
                    ? () {
                        Haptics.success();
                        widget.onCreate(
                          _ctrl.text.trim(),
                          _energy,
                          Duration(minutes: _minutes),
                        );
                      }
                    : null,
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('slot it in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
              Text('${DateFormat.jm().format(start)} · $gapStr free - pick something to slot in.',
                  style: Theme.of(sheetContext).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.lg),
              // Writing your own comes first: the backlog is a list of things
              // you already thought of, and this is for the thing you just did.
              OmTappable(
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _showNewBlockSheet(context, at: start, maxDuration: gap);
                },
                pressedScale: 0.98,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: c.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: Row(
                    children: [
                      Icon(OmIcons.byName('plus'), size: 18, color: Colors.white),
                      const SizedBox(width: AppSpacing.md),
                      const Expanded(
                        child: Text('write a new task',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              if (items.isEmpty)
                const OmEmptyState(message: 'nothing else in the backlog right now.')
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
