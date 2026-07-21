import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/alerts_provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/om_icons.dart';
import '../../models/task.dart';
import '../../providers/energy_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/memory_provider.dart';
import '../../providers/mood_provider.dart';
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
import 'widgets/memory_card.dart';
import 'widgets/mood_bar.dart';
import 'widgets/progress_bars.dart';
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

  /// The check-in is asked once, on the first open of the day. [_asked] guards
  /// against re-prompting when Home rebuilds, and the provider's own
  /// [MoodProvider.needsCheckIn] guards against asking again tomorrow morning
  /// if they already logged one.
  bool _asked = false;

  void _maybeAskMood(BuildContext context) {
    if (_asked) return;
    final mood = context.read<MoodProvider>();
    if (!mood.needsCheckIn) return;
    _asked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showMoodCheckIn(context);
    });
  }

  /// The memory rewrites itself once a day rather than waiting for someone to
  /// notice a refresh button. A picture of you that only updates when you ask
  /// it to is a picture that is usually wrong.
  bool _refreshed = false;

  void _maybeRefreshMemory(BuildContext context) {
    if (_refreshed) return;
    final memory = context.read<MemoryProvider>();
    if (!memory.isStale || memory.refreshing) return;
    _refreshed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MemoryCard.refreshFrom(context, haptic: false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final energy = context.watch<EnergyProvider>().current;
    final c = context.omColors;
    // Watched, so the prompt fires as soon as stored moods have loaded.
    context.watch<MoodProvider>();
    _maybeAskMood(context);
    // Watched too, so the pass fires once the stored memory has loaded and we
    // actually know how old it is.
    context.watch<MemoryProvider>();
    _maybeRefreshMemory(context);

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
            const HomeHero(),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: VibePill(energy: energy, onTap: () => showEnergyPicker(context)),
            ),
            const SizedBox(height: AppSpacing.xl),
            const ProgressBars(),
            const MoodBar(),
            const MemoryCard(),

            const OmSectionHeader('your goals'),
            const GoalAchievementCard(),
            const GoalsList(),
            const BrainDumpCard(),

            const OmSectionHeader('do this now'),
            const QuickActions(),

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
                : () {
              final tasks = context.read<TaskProvider>();
              // Surface the goal step belonging to *this* day before packing,
              // so planning a future day schedules that day's step rather than
              // today's.
              context.read<GoalProvider>().showDay(tasks.selectedDate);
              tasks.autoScheduleDay(
                settings.wakeUpTime,
                settings.sleepTime,
                context.read<AlertsProvider>(),
                settings.selectedRingtone,
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
