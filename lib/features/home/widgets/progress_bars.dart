import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_glass.dart';

/// The two numbers that answer "how am I doing?" without making you count:
/// how much of today is ticked off, and how far the goal plans have come.
///
/// Percentages are shown as well as bars. A bar alone reads as vibes; an ADHD
/// brain that is behind wants to know *how far* behind, and one that is ahead
/// deserves to see the number.
class ProgressBars extends StatelessWidget {
  const ProgressBars({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final goals = context.watch<GoalProvider>();

    // Today = real blocks only. Wake and sleep are the frame of the day, not
    // work, and counting them would make an empty day look 40% done.
    final today = tasks.todaySchedule.where((t) => !t.isAnchor).toList();
    final doneToday = tasks
        .scheduleOn(DateTime.now(), includeDone: true)
        .where((t) => !t.isAnchor && t.done)
        .length;
    final totalToday = today.length + doneToday;
    final todayFrac = totalToday == 0 ? 0.0 : doneToday / totalToday;

    final hasGoals = goals.totalSteps > 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: context.isDark ? 0.4 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: OmGlass(
          borderRadius: 24,
          blur: 26,
          opacity: context.isDark ? 0.34 : 0.62,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            children: [
              _Bar(
                label: 'today',
                caption: totalToday == 0
                    ? 'nothing blocked in yet'
                    : '$doneToday of $totalToday done',
                fraction: todayFrac,
                colors: [c.accent, Color.lerp(c.accent, c.primary, 0.5)!],
              ),
              if (hasGoals) ...[
                const SizedBox(height: 16),
                _Bar(
                  label: 'your goals',
                  caption: goals.onTrack
                      ? '${goals.doneSteps} of ${goals.totalSteps} steps · on track'
                      : '${goals.doneSteps} of ${goals.totalSteps} steps · behind the plan',
                  fraction: goals.overallProgress,
                  colors: [c.primary, Color.lerp(c.primary, c.accent, 0.45)!],
                  // The faint marker showing where the plan expected them to be
                  // by today - "70%" means nothing without it.
                  expected: goals.expectedProgress,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.label,
    required this.caption,
    required this.fraction,
    required this.colors,
    this.expected,
  });

  final String label;
  final String caption;
  final double fraction;
  final List<Color> colors;
  final double? expected;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final pct = (fraction.clamp(0.0, 1.0) * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            Text(
              '$pct%',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: colors.first,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return SizedBox(
              height: 10,
              child: Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: c.ringTrack,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeOutCubic,
                    tween: Tween(end: fraction.clamp(0.0, 1.0)),
                    builder: (context, value, _) => Container(
                      width: width * value,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: colors),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  if (expected != null && expected! > 0 && expected! < 1)
                    Positioned(
                      left: (width * expected!.clamp(0.0, 1.0)) - 1,
                      top: -2,
                      bottom: -2,
                      child: Container(width: 2, color: c.text2.withValues(alpha: 0.55)),
                    ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 6),
        Text(caption, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
      ],
    );
  }
}
