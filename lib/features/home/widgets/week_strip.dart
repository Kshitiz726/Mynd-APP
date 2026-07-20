import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_tappable.dart';

/// The week rail above the timeline: seven day pills, the selected one filled.
///
/// Anchored to the current week rather than to a scrolling infinite calendar,
/// because the point is to glance at the days around today, not to plan a month.
class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TaskProvider>();
    final selected = tasks.selectedDate;
    final today = DateTime.now();

    // Monday-first week containing the selected day.
    final monday = DateTime(selected.year, selected.month, selected.day)
        .subtract(Duration(days: selected.weekday - 1));
    final days = [for (var i = 0; i < 7; i++) monday.add(Duration(days: i))];

    return SizedBox(
      height: 68,
      child: Row(
        children: [
          for (final day in days)
            Expanded(
              child: _DayPill(
                day: day,
                selected: _sameDay(day, selected),
                isToday: _sameDay(day, today),
                // A dot means the day already has blocks on it, so an empty
                // week is visibly empty instead of silently so.
                hasBlocks: tasks.scheduleOn(day).isNotEmpty,
                onTap: () {
                  Haptics.select();
                  tasks.selectDate(day);
                },
              ),
            ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class _DayPill extends StatelessWidget {
  const _DayPill({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.hasBlocks,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final bool hasBlocks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final fg = selected ? Colors.white : c.text;

    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.94,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: selected ? c.text : c.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? Colors.transparent
                  : isToday
                      ? c.primary.withValues(alpha: 0.45)
                      : c.border,
              width: isToday && !selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${day.day}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: fg,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat.E().format(day),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected ? Colors.white70 : c.text2,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 3),
              // Reserve the dot's space always, so pills don't jump height.
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasBlocks
                      ? (selected ? Colors.white : c.primary)
                      : Colors.transparent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
