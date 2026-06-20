import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/alerts_provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../models/task.dart';
import '../../providers/energy_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_chip.dart';
import '../../widgets/om_states.dart';
import '../../widgets/vibe_pill.dart';
import 'widgets/day_timeline.dart';
import 'widgets/energy_sheet.dart';
import 'widgets/home_banners.dart';
import 'widgets/home_dashboard.dart';
import 'widgets/task_tile.dart';

/// The "Today" dashboard — the app's home base.
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
        // A single soft, radiant peach glow blooming from the top — no hard
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
      return OmEmptyState(message: 'nothing $phrase — wanna add a 2-min win?');
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
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _pickTime(context, settings.wakeUpTime, settings.setWakeUpTime),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.wb_sunny_rounded, size: 16, color: c.text2),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('Wake: ${settings.wakeUpTime.format(context)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _pickTime(context, settings.sleepTime, settings.setSleepTime),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                child: Row(
                  children: [
                    Icon(Icons.nights_stay_rounded, size: 16, color: c.text2),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('Sleep: ${settings.sleepTime.format(context)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.primary,
              side: BorderSide(color: c.primary),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              minimumSize: const Size(0, 32),
            ),
            onPressed: () {
              context.read<GoalProvider>().refreshTodayTasks();
              context.read<TaskProvider>().autoScheduleDay(
                settings.wakeUpTime, 
                settings.sleepTime,
                context.read<AlertsProvider>(),
                settings.selectedRingtone,
              );
            },
            child: const Text('Auto-Schedule AI', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
