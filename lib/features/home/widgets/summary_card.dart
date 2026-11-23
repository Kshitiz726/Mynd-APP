import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/toast.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_card.dart';
import '../../../widgets/om_tappable.dart';
import 'goal_sheet.dart';

/// The prominent "Up Next" card highlighting the single next scheduled block -
/// a focus anchor that answers "what do I do *right now*?".
class UpNextBanner extends StatefulWidget {
  const UpNextBanner({super.key});

  @override
  State<UpNextBanner> createState() => _UpNextBannerState();
}

class _UpNextBannerState extends State<UpNextBanner> {
  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final task = tasks.upNext;

    if (task == null) {
      return OmCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Center(
          child: Text("you're all clear! nothing up next.", style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
        ),
      );
    }

    final timeStr = DateFormat.jm().format(task.startTime!);
    final durationMins = task.duration?.inMinutes ?? 60;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: task.done ? 0.5 : 1,
      child: OmCard(
        padding: EdgeInsets.zero,
        onTap: () => Toast.show(context, 'opens next scheduled item details'),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: c.primary),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(OmIcons.byName('activity'), size: 14, color: c.primary),
                                const SizedBox(width: 8),
                                Text('UP NEXT',
                                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                          color: c.primary,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 1.2,
                                          fontSize: 10,
                                        )),
                              ],
                            ),
                            Text(timeStr, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.text2, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    task.title,
                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                          decoration: task.done ? TextDecoration.lineThrough : null,
                                        ),
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Icon(task.energy.icon, size: 13, color: c.text2),
                                      const SizedBox(width: 6),
                                      Text('${task.energy.label} • $durationMins min', style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                      )),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            OmTappable(
                              feedback: OmTapFeedback.none,
                              pressedScale: 0.85,
                              onTap: () {
                                tasks.toggleDone(task);
                                task.done ? Haptics.success() : Haptics.light();
                                Toast.show(context, task.done ? 'task marked done!' : 'marked not done');
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                curve: Curves.easeOutCubic,
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: task.done ? c.success : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: task.done ? c.success : c.border.withValues(alpha: 0.8), width: 2),
                                  boxShadow: task.done
                                      ? [BoxShadow(color: c.success.withValues(alpha: context.isDark ? 0.18 : 0.4), blurRadius: 10, offset: const Offset(0, 3))]
                                      : null,
                                ),
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 320),
                                  transitionBuilder: (child, anim) => ScaleTransition(
                                    scale: CurvedAnimation(parent: anim, curve: Curves.elasticOut),
                                    child: child,
                                  ),
                                  child: task.done
                                      ? Icon(OmIcons.byName('check'), key: const ValueKey('d'), size: 17, color: OmColors.onFill(c.success))
                                      : const SizedBox.shrink(key: ValueKey('e')),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The "2 goals on the go · 6 tasks today · 1 done" summary with quick actions.
class SummaryCard extends StatelessWidget {
  const SummaryCard({super.key, required this.onAddTask});

  final VoidCallback onAddTask;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final goalCount = context.watch<GoalProvider>().activeCount;

    return OmCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: c.primaryTint, width: 5),
            ),
            child: Text('$goalCount',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(color: c.primary, fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$goalCount goals on the go',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text('${tasks.totalToday} tasks today · ${tasks.doneCount} done',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w500)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _MiniChip(label: '+ task', onTap: onAddTask),
              const SizedBox(height: 8),
              _MiniChip(label: '+ goal', onTap: () => showAddGoalSheet(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      pressedScale: 0.92,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border.withValues(alpha: 0.5)),
        ),
        child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.text,
        )),
      ),
    );
  }
}

