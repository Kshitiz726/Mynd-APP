import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../providers/streak_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';

/// The whole history behind the number.
///
/// A streak counter with nothing behind it asks to be taken on faith. This is
/// the receipt: every day you showed up, and - more usefully - every day you
/// did not, because the gap is what explains why the number is what it is.
Future<void> showStreakCalendar(BuildContext context) {
  Haptics.light();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _StreakSheet(),
  );
}

class _StreakSheet extends StatefulWidget {
  const _StreakSheet();

  @override
  State<_StreakSheet> createState() => _StreakSheetState();
}

class _StreakSheetState extends State<_StreakSheet> {
  late DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _shift(int months) {
    Haptics.light();
    setState(() => _month = DateTime(_month.year, _month.month + months));
  }

  /// There is nothing to see in next month, and letting people page forever
  /// into empty grids makes the calendar feel broken rather than finished.
  bool get _canGoForward {
    final now = DateTime.now();
    return _month.isBefore(DateTime(now.year, now.month));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final streak = context.watch<StreakProvider>();

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: OmGlass(
          borderRadius: 28,
          elevated: true,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(
                  color: c.text2.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Row(
                children: [
                  _Stat(
                    value: '${streak.currentStreak}',
                    label: streak.todayPending
                        ? 'day streak · today pending'
                        : 'day streak',
                    accent: true,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  _Stat(
                      value: '${streak.longestStreak}', label: 'longest streak'),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              Row(
                children: [
                  _NavButton(icon: 'chevL', onTap: () => _shift(-1)),
                  Expanded(
                    child: Text(
                      DateFormat.yMMMM().format(_month),
                      textAlign: TextAlign.center,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  _NavButton(
                    icon: 'chevR',
                    onTap: _canGoForward ? () => _shift(1) : null,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              _MonthGrid(month: _month, streak: streak),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'a day counts when you check in or finish a task.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.text2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, this.accent = false});

  final String value;
  final String label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
        decoration: BoxDecoration(
          color: (accent ? c.accent : c.primary).withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(OmIcons.byName('flame'),
                    size: 18, color: accent ? c.accent : c.primary),
                const SizedBox(width: 6),
                Text(value,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: accent ? c.accent : c.primary,
                        )),
              ],
            ),
            const SizedBox(height: 2),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.text2)),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({required this.icon, required this.onTap});

  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      pressedScale: onTap == null ? 1.0 : 0.9,
      child: Opacity(
        opacity: onTap == null ? 0.3 : 1,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: c.surfaceAlt.withValues(alpha: 0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(OmIcons.byName(icon), size: 18, color: c.text2),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({required this.month, required this.streak});

  final DateTime month;
  final StreakProvider streak;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final first = DateTime(month.year, month.month);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // DateTime.weekday is 1=Mon..7=Sun; the grid starts on Monday.
    final leading = first.weekday - 1;

    final labels = ['m', 't', 'w', 't', 'f', 's', 's'];

    return Column(
      children: [
        Row(
          children: [
            for (final l in labels)
              Expanded(
                child: Center(
                  child: Text(l,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Color.lerp(c.text2, c.text, 0.4),
                            fontWeight: FontWeight.w800,
                          )),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            childAspectRatio: 1,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: leading + daysInMonth,
          itemBuilder: (context, i) {
            if (i < leading) return const SizedBox.shrink();
            final dayNum = i - leading + 1;
            final day = DateTime(month.year, month.month, dayNum);
            final done = streak.isComplete(day);
            final isToday = day == today;
            final future = day.isAfter(today);

            return _DayCell(
              day: dayNum,
              done: done,
              isToday: isToday,
              future: future,
            );
          },
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.done,
    required this.isToday,
    required this.future,
  });

  final int day;
  final bool done;
  final bool isToday;
  final bool future;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Container(
      decoration: BoxDecoration(
        // A completed day carries a warm coral wash strong enough to read as
        // filled on the translucent sheet, not a faint tint that disappears
        // into the glass.
        color: done
            ? c.accent.withValues(alpha: context.isDark ? 0.30 : 0.22)
            // Today, before it is earned, gets a soft brand wash so "where I
            // am" is legible even on the days the outline alone washed out.
            : isToday
                ? c.primary.withValues(alpha: context.isDark ? 0.20 : 0.10)
                : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        // Today is outlined rather than filled, so "where I am" and "what I
        // did" never compete for the same visual language.
        border: isToday
            ? Border.all(color: c.primary, width: 1.8)
            : null,
      ),
      child: Center(
        child: done
            ? Icon(OmIcons.byName('flame'), size: 19, color: c.accent)
            : Text(
                '$day',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      // Past and present days sit at full text colour so the
                      // grid is actually readable; a day still to come is dimmed
                      // rather than absent, because it is not a day you missed.
                      color: future
                          ? c.text2.withValues(alpha: 0.45)
                          : (isToday ? c.primary : c.text),
                      fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
      ),
    );
  }
}
