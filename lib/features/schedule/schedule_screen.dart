import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/calendar_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_states.dart';
import '../home/home_screen.dart';
import '../home/widgets/day_timeline.dart';
import '../home/widgets/home_dashboard.dart';
import '../home/widgets/week_strip.dart';
import 'widgets/now_strip.dart';

/// The schedule tab: what to do next, the week rail, the day's blocks, and the
/// backlog they are drawn from.
///
/// Split out of Home so the two have one job each. Home is "how am I doing",
/// this is "what happens when".
///
/// The one actionable task leads, where the calendar invitation used to sit.
/// That invitation was a prompt for something most people do once, occupying
/// the top of a screen they open every day; it lives in Settings under
/// Connections now, with the rest of "what has access to what". What is left at
/// the top is the thing the screen is actually for.
class ScheduleScreen extends StatefulWidget {
  const ScheduleScreen({super.key});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  DateTime? _syncedFor;

  @override
  void initState() {
    super.initState();
    // The day-pull used to belong to the calendar card, which has moved to
    // Settings. Without moving this with it, connecting a calendar would stop
    // putting anything on the timeline - the feature would look connected and
    // do nothing.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pullDay());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Browsing to another day has to pull that day too.
    final day = context.watch<TaskProvider>().selectedDate;
    if (_syncedFor == null || !_sameDay(_syncedFor!, day)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pullDay());
    }
  }

  Future<void> _pullDay() async {
    if (!mounted) return;
    final cal = context.read<CalendarProvider>();
    if (!cal.connected) return;
    final tasks = context.read<TaskProvider>();
    final day = tasks.selectedDate;
    _syncedFor = day;
    final imported = await cal.importDay(day);
    if (!mounted) return;
    tasks.mergeCalendar(imported, day);
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();

    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -1.05),
                radius: 1.25,
                colors: [
                  const Color(0xFFE8E4FF), // cool lilac, so the tab reads apart from Home's peach
                  Color.lerp(const Color(0xFFE8E4FF), c.surface, 0.55)!,
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
            const OmSectionHeader('do this now'),
            const QuickActions(),

            // The mood check-in is parked, not deleted. It is a good feature in
            // the wrong place: this screen is about the clock, and being asked
            // how you feel in the middle of it interrupts the one thing you
            // came here to read. It wants a home of its own.
            // const OmSectionHeader('how are you today?'),
            // const MoodPicker(),

            const OmSectionHeader('your day'),
            const SleepScheduleBarX(),
            const SizedBox(height: AppSpacing.sm),
            const WeekStrip(),
            const SizedBox(height: AppSpacing.md),
            const DayTimeline(),

            // Under the timeline, because it is the timeline read at one
            // specific minute: the answer you wanted from it without having to
            // find the current time yourself.
            const SizedBox(height: AppSpacing.md),
            const NowStrip(),

            const OmSectionHeader('backlog'),
            BacklogFiltersX(),
            const SizedBox(height: AppSpacing.lg),
            BacklogX(tasks: tasks),
          ],
        ),
      ],
    );
  }
}
