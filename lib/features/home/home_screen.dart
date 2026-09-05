import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/calendar_provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/task.dart';
import '../../providers/goal_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_chip.dart';
import '../../widgets/om_states.dart';
import '../../widgets/om_time_picker.dart';
import '../../widgets/om_tappable.dart';
import 'widgets/mynd_hero.dart';
import 'widgets/home_banners.dart';
import 'widgets/home_dashboard.dart';
import 'widgets/mood_picker.dart';
import 'widgets/motivation_card.dart';
import 'widgets/task_tile.dart';

/// The "Today" dashboard - the app's home base.
///
/// Composition (reference-styled): top bar → hero mascot + stat → vibe →
/// featured goal → do-this-now → your day timeline → backlog.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Push today's goal milestones onto the timeline as soon as Home mounts so
    // goal-derived tasks show up in the day and feed Auto-Schedule.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<GoalProvider>().refreshTodayTasks();
    });
  }

  // The check-in used to open as a modal sheet on the first launch of every
  // day. It is now the MoodPicker on the page instead: asking the question
  // before somebody has reached the app interrupts whatever they opened it to
  // do, and on the days worth noticing it is the most likely thing to be
  // swiped away. Present and answerable in one drag beats asked and dismissed.

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Stack(
      children: [
        // Home is the app's face, so it carries the brand rather than a neutral
        // wash: coral warming the top where the mascot sits, brand purple
        // cooling the bottom, and two off-centre blooms so the colour has a
        // direction instead of sitting there as a flat ramp.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: context.isDark
                    ? [
                        Color.lerp(c.accent, c.bg, 0.80)!,
                        Color.lerp(c.primary, c.bg, 0.84)!,
                        c.bg,
                      ]
                    : [
                        const Color(0xFFFFD9C2), // coral, warm
                        const Color(0xFFEADEFF), // brand lilac
                        const Color(0xFFF6F2FF),
                      ],
                stops: const [0.0, 0.55, 1.0],
              ),
            ),
          ),
        ),
        // Coral bloom behind the mascot.
        Positioned(
          top: -80,
          right: -60,
          child: _Bloom(color: c.accent, size: 300, alpha: context.isDark ? 0.22 : 0.42),
        ),
        // Brand bloom low-left, so the page is lit from two sides.
        Positioned(
          top: 260,
          left: -90,
          child: _Bloom(color: c.primary, size: 320, alpha: context.isDark ? 0.20 : 0.30),
        ),
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.screenTop,
            AppSpacing.screenH,
            AppSpacing.screenBottom,
          ),
          children: [
            const LowStimBanner(),
            const HomeTopBar(),
            const MyndHero(),
            // The one thing to do, first: it is the only item on this screen
            // that somebody can act on without deciding anything.
            const OmSectionHeader('do this now'),
            const QuickActions(),

            // Then the day's line, still on the first screen.
            const MotivationCard(),

            // The check-in, which takes one tap and can wait until the two
            // things above have been read.
            const MoodPicker(),

            const SizedBox(height: AppSpacing.md),

            // The "today" bars and the fortnight mood strip used to sit here.
            // Both restated something already on this screen - the day's
            // progress is in the card at the top, and today's mood is the
            // check-in - so they were a second, quieter answer to a question
            // already answered above.

            const OmSectionHeader('your goals'),
            const GoalAchievementCard(),
            const GoalsList(),
          ],
        ),
      ],
    );
  }
}

class BacklogFiltersX extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TaskProvider>();
    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        children: [
          for (final f in BacklogFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: OmChip(
                label: f.label,
                selected: tasks.filter == f,
                icon: f.energy?.icon,
                onTap: () => tasks.setFilter(f),
              ),
            ),
        ],
      ),
    );
  }
}

class BacklogX extends StatelessWidget {
  const BacklogX({required this.tasks});

  final TaskProvider tasks;

  @override
  Widget build(BuildContext context) {
    final cap = context.select<SettingsProvider, int>((s) => s.backlogCap);
    final items = tasks.backlog;

    if (items.isEmpty) {
      final f = tasks.filter;
      final phrase = f == BacklogFilter.all ? 'right now' : '${f.energy?.filterLabel ?? f.label} right now';
      return OmEmptyState(message: 'nothing $phrase - wanna add a 2-min win?');
    }

    final visible = items.take(cap).toList();
    final hidden = items.length - visible.length;

    return Column(
      children: [
        for (final t in visible) TaskTile(task: t),
        if (hidden > 0) ShowMoreX(count: hidden, items: items, cap: cap),
      ],
    );
  }
}

/// Reveals the capped-off tasks. Kept as a small stateful widget so the cap is
/// a soft default, not a hard wall.
class ShowMoreX extends StatefulWidget {
  const ShowMoreX({required this.count, required this.items, required this.cap});

  final int count;
  final List<Task> items;
  final int cap;

  @override
  State<ShowMoreX> createState() => ShowMoreStateX();
}

class ShowMoreStateX extends State<ShowMoreX> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    if (_expanded) {
      return Column(
        children: [for (final t in widget.items.skip(widget.cap)) TaskTile(task: t)],
      );
    }
    return TextButton(
      onPressed: () => setState(() => _expanded = true),
      child: Text('show ${widget.count} more',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.text2)),
    );
  }
}

class SleepScheduleBarX extends StatelessWidget {
  const SleepScheduleBarX();

  Future<void> _pickTime(BuildContext context, TimeOfDay current, ValueChanged<TimeOfDay> onChanged) async {
    final t = await showOmTimePicker(context: context, initialTime: current);
    if (t != null) onChanged(t);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final settings = context.watch<SettingsProvider>();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TimePillX(
              icon: 'sun',
              label: 'Wake',
              value: settings.wakeUpTime.format(context),
              onTap: () => _pickTime(context, settings.wakeUpTime, settings.setWakeUpTime),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TimePillX(
              icon: 'moon',
              label: 'Sleep',
              value: settings.sleepTime.format(context),
              onTap: () => _pickTime(context, settings.sleepTime, settings.setSleepTime),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OmTappable(
            // A day that has already happened is a record, so there is nothing
            // to plan on it.
            onTap: !context.watch<TaskProvider>().canPlan(context.watch<TaskProvider>().selectedDate)
                ? null
                : () async {
              final tasks = context.read<TaskProvider>();
              final cal = context.read<CalendarProvider>();
              // Surface the goal step belonging to *this* day before packing,
              // so planning a future day schedules that day's step rather than
              // today's.
              context.read<GoalProvider>().showDay(tasks.selectedDate);
              // Read the calendar BEFORE placing anything. Packing first and
              // checking after would mean the timeline briefly showed work on
              // top of a meeting, and whichever version somebody happened to
              // look at is the one they would believe. Empty when nothing is
              // connected, which packs exactly as it always did.
              final busy = await cal.busyOn(tasks.selectedDate);
              if (!context.mounted) return;
              final r = tasks.autoScheduleDay(
                settings.wakeUpTime,
                settings.sleepTime,
                context.read<AlertsProvider>(),
                settings.selectedRingtone,
                // Plan the day being looked at, not always today.
                day: tasks.selectedDate,
                busy: busy,
              );
              // Nothing fitting before bedtime looks identical to a button that
              // did not work, so say which it was.
              if (r.noRoom > 0) {
                Toast.show(
                  context,
                  r.placed == 0
                      ? busy.isEmpty
                          ? 'no room left before bed - try tomorrow'
                          : 'your calendar is full today'
                      : '${r.noRoom} left over - no gap big enough',
                );
              }
              // Push after placing, so the calendar shows what the timeline
              // shows. Failures here are quiet by design: a task that did not
              // reach the calendar is still planned, and twenty toasts for one
              // refusing calendar helps nobody.
              await cal.pushDay(tasks.daySchedule, tasks.selectedDate);
            },
            feedback: OmTapFeedback.medium,
            pressedScale: 0.95,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                gradient: c.brandGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                boxShadow: [
                  BoxShadow(
                    color: c.primary.withValues(alpha: 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(OmIcons.byName('sparkles'), size: 15, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('Auto-Schedule',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A compact tappable pill showing a labelled time (Wake / Sleep) on the day
/// header. Opens a time picker on tap.
class TimePillX extends StatelessWidget {
  const TimePillX({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      pressedScale: 0.96,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: c.border.withValues(alpha: 0.7)),
        ),
        child: Row(
          children: [
            Icon(OmIcons.byName(icon), size: 15, color: c.text2),
            const SizedBox(width: 6),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text('$label · $value',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A soft radial bloom of brand colour. Blurring is expensive on a scrolling
/// page, so the softness comes from the gradient's own falloff.
class _Bloom extends StatelessWidget {
  const _Bloom({required this.color, required this.size, required this.alpha});

  final Color color;
  final double size;
  final double alpha;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 1.0],
            ),
          ),
        ),
      ),
    );
  }
}
