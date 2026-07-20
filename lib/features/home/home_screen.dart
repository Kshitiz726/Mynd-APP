import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/alerts_provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/om_icons.dart';
import '../../models/task.dart';
import '../../providers/energy_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_chip.dart';
import '../../widgets/om_states.dart';
import '../../widgets/om_tappable.dart';
import '../../widgets/vibe_pill.dart';
import 'widgets/day_timeline.dart';
import 'widgets/energy_sheet.dart';
import 'widgets/home_banners.dart';
import 'widgets/home_dashboard.dart';
import 'widgets/task_tile.dart';
import 'widgets/week_strip.dart';

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

  @override
  Widget build(BuildContext context) {
    final energy = context.watch<EnergyProvider>().current;
    final tasks = context.watch<TaskProvider>();

    final c = context.omColors;

    return Stack(
      children: [
        // A single soft, radiant peach glow blooming from the top - no hard
        // circles, just a clean radial wash that melts into the surface.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.05),
                radius: 1.25,
                colors: [
                  const Color(0xFFFFE6D0), // warm peach core
                  Color.lerp(const Color(0xFFFFE6D0), c.surface, 0.55)!,
                  c.surface,
                ],
                stops: const [0.0, 0.42, 0.85],
              ),
            ),
          ),
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
            const HomeHero(),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: VibePill(energy: energy, onTap: () => showEnergyPicker(context)),
            ),
            const SizedBox(height: AppSpacing.xl),
            const OmSectionHeader('your goals'),
            const GoalAchievementCard(),
            const GoalsList(),
            const BrainDumpCard(),

            const OmSectionHeader('do this now'),
            const QuickActions(),

            const OmSectionHeader('your day', trailing: 'view all'),
            const _SleepScheduleBar(),
            const SizedBox(height: AppSpacing.sm),
            const WeekStrip(),
            const SizedBox(height: AppSpacing.md),
            const DayTimeline(),

            const OmSectionHeader('backlog'),
            _BacklogFilters(),
            const SizedBox(height: AppSpacing.lg),
            _Backlog(tasks: tasks),
          ],
        ),
      ],
    );
  }
}

class _BacklogFilters extends StatelessWidget {
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

class _Backlog extends StatelessWidget {
  const _Backlog({required this.tasks});

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
        if (hidden > 0) _ShowMore(count: hidden, items: items, cap: cap),
      ],
    );
  }
}

/// Reveals the capped-off tasks. Kept as a small stateful widget so the cap is
/// a soft default, not a hard wall.
class _ShowMore extends StatefulWidget {
  const _ShowMore({required this.count, required this.items, required this.cap});

  final int count;
  final List<Task> items;
  final int cap;

  @override
  State<_ShowMore> createState() => _ShowMoreState();
}

class _ShowMoreState extends State<_ShowMore> {
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

class _SleepScheduleBar extends StatelessWidget {
  const _SleepScheduleBar();

  Future<void> _pickTime(BuildContext context, TimeOfDay current, ValueChanged<TimeOfDay> onChanged) async {
    final t = await showTimePicker(context: context, initialTime: current);
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
            child: _TimePill(
              icon: 'sun',
              label: 'Wake',
              value: settings.wakeUpTime.format(context),
              onTap: () => _pickTime(context, settings.wakeUpTime, settings.setWakeUpTime),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _TimePill(
              icon: 'moon',
              label: 'Sleep',
              value: settings.sleepTime.format(context),
              onTap: () => _pickTime(context, settings.sleepTime, settings.setSleepTime),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          OmTappable(
            onTap: () {
              context.read<GoalProvider>().refreshTodayTasks();
              final tasks = context.read<TaskProvider>();
              tasks.autoScheduleDay(
                settings.wakeUpTime,
                settings.sleepTime,
                context.read<AlertsProvider>(),
                settings.selectedRingtone,
                // Habits are part of the day, so auto-schedule lays them in too.
                habitBoards: context.read<HabitProvider>().boards,
                // Plan the day being looked at, not always today.
                day: tasks.selectedDate,
              );
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
class _TimePill extends StatelessWidget {
  const _TimePill({
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
