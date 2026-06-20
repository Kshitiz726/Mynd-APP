import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/toast.dart';
import '../../../models/habit.dart';
import '../../../providers/habit_provider.dart';
import '../../../widgets/om_tappable.dart';

/// Snap-scrolling habit boards ("Morning / Focus / Evening") with tab
/// indicators above. Mirrors the prototype's `.habits-snap` + `.board-tabs`.
class HabitsStrip extends StatefulWidget {
  const HabitsStrip({super.key});

  @override
  State<HabitsStrip> createState() => _HabitsStripState();
}

class _HabitsStripState extends State<HabitsStrip> {
  final _controller = PageController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    _controller.animateToPage(index,
        duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final habits = context.watch<HabitProvider>();
    final boards = habits.boards;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Tabs.
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: boards.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (context, i) => _BoardTab(
              label: boards[i].name,
              active: i == habits.activeBoard,
              onTap: () => _goTo(i),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 200,
          child: PageView.builder(
            controller: _controller,
            onPageChanged: habits.setActiveBoard,
            itemCount: boards.length,
            itemBuilder: (context, i) => _BoardPage(board: boards[i]),
          ),
        ),
      ],
    );
  }
}

class _BoardTab extends StatelessWidget {
  const _BoardTab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      pressedScale: 0.93,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? c.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          boxShadow: active
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 10, offset: const Offset(0, 4))]
              : null,
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: active ? c.text : c.text2,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
        ),
      ),
    );
  }
}

class _BoardPage extends StatelessWidget {
  const _BoardPage({required this.board});

  final HabitBoard board;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 24,
      crossAxisSpacing: 12,
      childAspectRatio: 0.74,
      children: [for (final h in board.items) HabitTile(habit: h)],
    );
  }
}

/// A single habit chip with an animated completion ring and a check that
/// crossfades in. Timer-type habits launch a focus session instead of toggling.
class HabitTile extends StatelessWidget {
  const HabitTile({super.key, required this.habit});

  final Habit habit;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final habits = context.read<HabitProvider>();

    return OmTappable(
      feedback: OmTapFeedback.none, // we fire a tailored haptic below
      pressedScale: 0.9,
      onTap: () {
        if (habit.kind == HabitKind.timer) {
          Haptics.select();
          // Focus feature ships in the next pass; for now confirm the intent.
          Toast.show(context, 'starting ${habit.name} · ${habit.minutes} min focus');
          return;
        }
        habit.done ? Haptics.light() : Haptics.success();
        habits.toggle(habit);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            width: AppSizes.habitTile,
            height: AppSizes.habitTile,
            decoration: BoxDecoration(
              color: habit.done ? habit.color.withValues(alpha: 0.12) : c.surface,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: habit.done ? habit.color : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: habit.done
                      ? habit.color.withValues(alpha: 0.22)
                      : Colors.black.withValues(alpha: 0.08),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 320),
                transitionBuilder: (child, anim) => ScaleTransition(
                  scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
                  child: child,
                ),
                child: habit.done
                    ? Icon(OmIcons.byName('check'), key: const ValueKey('done'), size: 28, color: habit.color)
                    : Icon(OmIcons.byName(habit.iconName), key: const ValueKey('icon'), size: 24, color: habit.color),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            habit.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: c.text,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
