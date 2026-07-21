import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/services/api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../models/goal.dart';
import '../../../models/task.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_avatar.dart';
import '../../../widgets/om_card.dart';
import '../../../widgets/om_mascot.dart';
import '../../../widgets/om_states.dart';
import '../../../widgets/om_tappable.dart';
import '../../../widgets/shimmer_swipe.dart';
import '../search/global_search_screen.dart';
import 'goal_sheet.dart';
import 'brain_dump_sheet.dart';
import 'edit_task_sheet.dart';

/// Top chrome for the Today dashboard: the user's avatar, a global app-search
/// field, and a "berries" momentum pill - mirroring the reference's
/// avatar · search · points header.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final goalsDone =
        context.watch<GoalProvider>().goals.fold<int>(0, (s, g) => s + g.doneCount);
    // A light, derived momentum score so the pill reflects real progress.
    final berries = tasks.doneCount * 10 + goalsDone * 20;

    final name = ApiConfig.instance.displayName ?? 'friend';
    final userId = ApiConfig.instance.userId ?? name;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          OmTappable(
            onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
            pressedScale: 0.9,
            child: OmAvatar(
              userId: userId,
              fallbackInitial: initial,
              fallbackColor: c.primary,
              size: 44,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: OmTappable(
              onTap: () => GlobalSearchScreen.open(context),
              feedback: OmTapFeedback.light,
              pressedScale: 0.98,
              child: Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: c.border.withValues(alpha: 0.7)),
                ),
                child: Row(
                  children: [
                    Icon(OmIcons.byName('search'), size: 18, color: c.text2),
                    const SizedBox(width: 10),
                    Text('Search OurMynd',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: c.primaryTint,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              children: [
                Icon(OmIcons.byName('flame'), size: 18, color: c.accent),
                const SizedBox(width: 6),
                Text('$berries',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: c.primary,
                          fontWeight: FontWeight.w800,
                        )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The hero: the mascot with a streak flame, a friendly bubble, and the day's
/// headline stat ("N done today" + scheduled/goals breakdown).
class HomeHero extends StatelessWidget {
  const HomeHero({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final goals = context.watch<GoalProvider>().activeCount;
    final done = tasks.doneCount;
    final scheduled = tasks.daySchedule.length;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Soft halo behind the mascot.
              Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [c.primaryTint.withValues(alpha: 0.7), c.bg.withValues(alpha: 0)],
                  ),
                ),
              ),
              const OmMascot(size: 116),
              // Streak flame badge.
              Positioned(
                bottom: 2,
                right: 44,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c.accent, Color.lerp(c.accent, Colors.red, 0.25)!],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    boxShadow: [
                      BoxShadow(color: c.accent.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(OmIcons.byName('flame'), size: 15, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('$done',
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
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('$done done today',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 30)),
        const SizedBox(height: 4),
        Text('$scheduled scheduled · $goals goals',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// The featured progress card - the user's primary active goal rendered like the
/// reference's "Get rid of your back pain · Session 4 · 100" tile, with milestone
/// progress dots. Falls back to a "set a goal" CTA when there are none.
class FeaturedGoalCard extends StatelessWidget {
  const FeaturedGoalCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final goalProvider = context.watch<GoalProvider>();
    Goal? goal;
    for (final g in goalProvider.goals) {
      if (!g.isComplete) {
        goal = g;
        break;
      }
    }

    if (goal == null) {
      return OmTappable(
        onTap: () => showAddGoalSheet(context),
        feedback: OmTapFeedback.light,
        pressedScale: 0.98,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: c.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.card),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.3),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
                ),
                child: Icon(OmIcons.byName('target'), color: Colors.white, size: 30),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Set your first goal',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            )),
                    const SizedBox(height: 4),
                    Text('we’ll break it into daily steps',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: 0.9),
                            )),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
                child: Icon(OmIcons.byName('plus'), color: Colors.white, size: 22),
              ),
            ],
          ),
        ),
      );
    }

    final g = goal;
    return OmCard.hero(
      tint: c.primary,
      padding: const EdgeInsets.all(18),
      onTap: () => Navigator.of(context).pushNamed(AppRoutes.profile),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 19)),
                const SizedBox(height: 6),
                Text('Step ${g.doneCount} of ${g.total}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
                const SizedBox(height: 12),
                _ProgressDots(total: g.total, done: g.doneCount),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(OmIcons.byName('flame'), size: 15, color: c.accent),
                    const SizedBox(width: 5),
                    Text('${(g.progress * 100).round()}% there',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: c.primary,
                              fontWeight: FontWeight.w700,
                            )),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(20)),
            alignment: Alignment.center,
            child: Icon(OmIcons.byName('activity'), color: c.primary, size: 30),
          ),
        ],
      ),
    );
  }
}

/// Tracks overall goal achievement - how much of every goal's daily-step plan
/// has been completed on the way to each deadline, plus whether the user is
/// keeping pace. Sits above the featured goal so the big picture comes first.
class GoalAchievementCard extends StatelessWidget {
  const GoalAchievementCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final gp = context.watch<GoalProvider>();
    if (gp.goals.isEmpty) return const SizedBox.shrink();

    final progress = gp.overallProgress.clamp(0.0, 1.0);
    final pct = (progress * 100).round();
    final onTrack = gp.onTrack;
    final statusColor = onTrack ? c.success : c.accent;
    final statusText = onTrack ? 'on track' : 'a little behind';

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: OmCard(
        child: Row(
          children: [
            SizedBox(
              width: 66,
              height: 66,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 66,
                    height: 66,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: progress),
                      duration: const Duration(milliseconds: 700),
                      curve: Curves.easeOutCubic,
                      builder: (_, v, __) => CircularProgressIndicator(
                        value: v,
                        strokeWidth: 7,
                        strokeCap: StrokeCap.round,
                        backgroundColor: c.ringTrack,
                        valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                      ),
                    ),
                  ),
                  Text('$pct%',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          )),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('goal achievement',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 3),
                  Text('${gp.doneSteps} of ${gp.totalSteps} daily steps done',
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 9),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          onTrack ? OmIcons.byName('trending-up') : OmIcons.byName('clock'),
                          size: 13,
                          color: statusColor,
                        ),
                        const SizedBox(width: 5),
                        Text(statusText,
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: statusColor,
                                  fontWeight: FontWeight.w800,
                                )),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots({required this.total, required this.done});

  final int total;
  final int done;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    const maxDots = 14;
    final count = total > maxDots ? maxDots : total;
    final doneShown = total > maxDots ? ((done / total) * maxDots).round() : done;
    return Row(
      children: [
        for (int i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.only(right: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: i < doneShown ? c.primary : c.primary.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

/// "do this now" - a single focus: the one task happening now (or next up).
/// Deliberately one card so there's no decision paralysis - the next thing,
/// nothing else. Falls back to the top backlog item when nothing is scheduled.
class QuickActions extends StatefulWidget {
  const QuickActions({super.key});

  @override
  State<QuickActions> createState() => _QuickActionsState();
}

class _QuickActionsState extends State<QuickActions> {
  Task? _displayTask;
  bool _isTransitioning = false;

  @override
  Widget build(BuildContext context) {
    final tasks = context.watch<TaskProvider>();
    final targetTask = tasks.upNext ?? (tasks.backlog.isNotEmpty ? tasks.backlog.first : null);

    // If we have a task displayed, and it was just marked done, delay the swap.
    if (_displayTask != null && _displayTask!.done && targetTask != _displayTask && !_isTransitioning) {
      _isTransitioning = true;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) {
          setState(() {
            _displayTask = targetTask;
            _isTransitioning = false;
          });
        }
      });
    } else if (!_isTransitioning) {
      _displayTask = targetTask;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _displayTask != null
              ? _ActionCard(key: ValueKey(_displayTask!.id), task: _displayTask!)
              : const OmEmptyState(key: ValueKey('empty'), message: 'take a breather - you’re all caught up!'),
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({super.key, required this.task});

  final Task task;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final color = task.isGoalTask ? c.primary : task.energy.color(context);
    final timeStr = task.startTime != null ? DateFormat.jm().format(task.startTime!) : 'anytime';

    return ShimmerSwipe(
      child: OmCard.hero(
        tint: color,
        padding: const EdgeInsets.all(12),
        onLongPress: () => showEditTaskSheet(context, task),
        onTap: () {
          Haptics.success();
          context.read<TaskProvider>().toggleDone(task);
        },
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                task.isGoalTask ? OmIcons.byName('activity') : task.energy.icon,
                color: color,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            decoration: task.done ? TextDecoration.lineThrough : null,
                          )),
                  const SizedBox(height: 2),
                  Text('${task.energy.label} · $timeStr',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12)),
                ],
              ),
            ),
            Icon(OmIcons.byName('chevR'), size: 18, color: c.text2),
          ],
        ),
      ),
    );
  }
}

/// The active-goals list - each goal as a row with a completion checkbox circle,
/// its deadline and step progress. Shows a clean empty state when there are no
/// goals yet. This is the simple, at-a-glance goals module on Home.
class GoalsList extends StatelessWidget {
  const GoalsList({super.key});

  @override
  Widget build(BuildContext context) {
    final gp = context.watch<GoalProvider>();
    if (gp.goals.isEmpty) return const _GoalsEmptyState();

    final active = gp.active;
    final done = gp.finished;

    return Column(
      children: [
        for (final g in active) _GoalRow(goal: g),
        // Finished goals fold away. A goal you have completed is a record, not
        // a task, and leaving it in the list means the thing you achieved
        // spends the rest of its life adding to the pile you are looking at.
        if (done.isNotEmpty) _FinishedGoals(goals: done),
        const SizedBox(height: AppSpacing.sm),
        const _AddGoalButton(),
      ],
    );
  }
}

/// A one-line disclosure for goals that are done.
class _FinishedGoals extends StatefulWidget {
  const _FinishedGoals({required this.goals});

  final List<Goal> goals;

  @override
  State<_FinishedGoals> createState() => _FinishedGoalsState();
}

class _FinishedGoalsState extends State<_FinishedGoals> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final n = widget.goals.length;
    return Column(
      children: [
        OmTappable(
          onTap: () {
            Haptics.light();
            setState(() => _open = !_open);
          },
          feedback: OmTapFeedback.none,
          pressedScale: 0.98,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(OmIcons.solid('check'), size: 15, color: c.success),
                const SizedBox(width: 8),
                Text(
                  '$n finished',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: c.text2,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Spacer(),
                AnimatedRotation(
                  duration: const Duration(milliseconds: 200),
                  turns: _open ? 0.25 : 0,
                  child: Icon(OmIcons.byName('chevR'), size: 15, color: c.text2),
                ),
              ],
            ),
          ),
        ),
        if (_open)
          for (final g in widget.goals) _GoalRow(goal: g),
      ],
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.goal});
  final Goal goal;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final complete = goal.isComplete;
    final due = DateFormat('MMM d').format(goal.targetDate);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: OmCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Completion checkbox circle
            OmTappable(
              pressedScale: 0.85,
              onTap: () {
                Haptics.success();
                context.read<GoalProvider>().toggleGoalComplete(goal.id);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: complete ? c.primary : Colors.transparent,
                  border: Border.all(color: complete ? c.primary : c.border, width: 2),
                ),
                child: complete
                    ? Icon(OmIcons.byName('check'), size: 16, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    goal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          decoration: complete ? TextDecoration.lineThrough : null,
                          color: complete ? c.text2 : c.text,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(OmIcons.byName('calendar'), size: 12, color: c.text2),
                      const SizedBox(width: 4),
                      Text('due $due · ${goal.doneCount}/${goal.total} steps',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Mini progress ring
            SizedBox(
              width: 26,
              height: 26,
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: goal.progress),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (_, v, __) => CircularProgressIndicator(
                  value: v,
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: c.ringTrack,
                  valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddGoalButton extends StatelessWidget {
  const _AddGoalButton();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmCard.hero(
      tint: c.primary,
      padding: const EdgeInsets.symmetric(vertical: 14),
      onTap: () => showAddGoalSheet(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(OmIcons.byName('plus'), size: 18, color: c.primary),
          const SizedBox(width: 8),
          Text('New goal',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: c.primary,
                    fontWeight: FontWeight.w800,
                  )),
        ],
      ),
    );
  }
}

/// Clean, professional empty state when no goals exist yet.
class _GoalsEmptyState extends StatelessWidget {
  const _GoalsEmptyState();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmCard(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 18),
      onTap: () => showAddGoalSheet(context),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [c.primaryTint, c.primary.withValues(alpha: 0.12)],
              ),
            ),
            child: Icon(OmIcons.byName('target'), color: c.primary, size: 30),
          ),
          const SizedBox(height: 14),
          Text('No active goals',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  )),
          const SizedBox(height: 4),
          Text("Set a goal - we'll break it into daily steps.",
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              gradient: c.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text('Set your first goal',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

/// A premium card inviting the user to brain dump.
class BrainDumpCard extends StatelessWidget {
  const BrainDumpCard({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: OmCard.hero(
        tint: c.primary,
        onTap: () => showBrainDumpSheet(context),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.primary, c.flow]),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(OmIcons.byName('sparkles'), color: Colors.white, size: 26),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Brain Dump',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text('Let AI organize your thoughts',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            Icon(OmIcons.byName('plus-circle'), color: c.primary, size: 24),
          ],
        ),
      ),
    );
  }
}
