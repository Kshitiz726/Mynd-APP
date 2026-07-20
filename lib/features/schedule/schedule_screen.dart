import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_states.dart';
import '../home/home_screen.dart';
import '../home/widgets/day_timeline.dart';
import '../home/widgets/week_strip.dart';

/// The schedule tab: the week rail, the day's blocks, and the backlog they are
/// drawn from.
///
/// Split out of Home so the two have one job each. Home is "how am I doing",
/// this is "what happens when".
class ScheduleScreen extends StatelessWidget {
  const ScheduleScreen({super.key});

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
            const OmSectionHeader('your day'),
            const SleepScheduleBarX(),
            const SizedBox(height: AppSpacing.sm),
            const WeekStrip(),
            const SizedBox(height: AppSpacing.md),
            const DayTimeline(),
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
