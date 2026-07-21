import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/api_config.dart';
import '../../../core/services/memory_snapshot.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/toast.dart';
import '../../../providers/coach_provider.dart';
import '../../../providers/community_provider.dart';
import '../../../providers/energy_provider.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/habit_provider.dart';
import '../../../providers/memory_provider.dart';
import '../../../providers/mood_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';
import '../../../widgets/text_editing_scope.dart';

/// "what I know about you" - the profile the AI keeps, shown to the person it
/// is about.
///
/// Anything that quietly steers the coach has to be visible and correctable, or
/// the user has no way to tell a helpful inference from a wrong one. So this
/// card puts the memory on the home screen, with edit and refresh a tap away.
class MemoryCard extends StatelessWidget {
  const MemoryCard({super.key});

  /// Rewrite the memory from everything the app can currently see.
  ///
  /// Shared by the refresh button and by Home's once-a-day automatic pass, so
  /// both read from exactly the same picture of the user.
  static Future<void> refreshFrom(BuildContext context, {bool haptic = true}) async {
    if (haptic) Haptics.medium();
    final memory = context.read<MemoryProvider>();
    final snapshot = buildMemorySnapshot(
      userName: memory.preferredName?.isNotEmpty == true
          ? memory.preferredName!
          : (ApiConfig.instance.displayName ?? 'friend'),
      tasks: context.read<TaskProvider>(),
      goals: context.read<GoalProvider>(),
      habits: context.read<HabitProvider>(),
      energy: context.read<EnergyProvider>(),
      community: context.read<CommunityProvider>(),
      mood: context.read<MoodProvider>(),
      // What they have actually been saying to the coach, in their own words.
      recentChat: context.read<CoachProvider>().recentTranscript(),
    );
    await memory.refresh(snapshot);
    if (context.mounted && memory.error != null) Toast.show(context, memory.error!);
  }

  Future<void> _refresh(BuildContext context) => refreshFrom(context);

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final memory = context.watch<MemoryProvider>();
    final m = memory.memory;

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
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      gradient: c.brandGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(OmIcons.byName('brain'), size: 16, color: Colors.white),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'what I know about you',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  if (memory.refreshing)
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
                    )
                  else ...[
                    _MiniAction(
                      icon: 'refresh',
                      tooltip: 'Update from what I have seen',
                      onTap: () => _refresh(context),
                    ),
                    const SizedBox(width: 4),
                    _MiniAction(
                      icon: 'edit',
                      tooltip: 'Edit this yourself',
                      onTap: () => showMemoryEditor(context),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              if (m.isEmpty)
                Text(
                  memory.refreshing
                      ? 'reading everything you have told me…'
                      : "I haven't written anything about you yet. Tap refresh and "
                          "I'll read your plans, goals and what you react to.",
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: c.text2,
                        height: 1.45,
                      ),
                )
              else
                Text(
                  m.text,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
              if (m.updatedAt != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      '${m.userEdited ? 'your words' : 'written by Mynd'} · '
                      '${DateFormat.MMMd().add_jm().format(m.updatedAt!)}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2),
                    ),
                    const Spacer(),
                    if (memory.parked.isNotEmpty)
                      OmTappable(
                        onTap: () => showParkedThoughts(context),
                        feedback: OmTapFeedback.none,
                        pressedScale: 0.96,
                        child: Text(
                          '${memory.parked.length} parked',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: c.primary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({required this.icon, required this.onTap, required this.tooltip});

  final String icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Tooltip(
      message: tooltip,
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none,
        pressedScale: 0.86,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
          child: Icon(OmIcons.byName(icon), size: 15, color: c.text2),
        ),
      ),
    );
  }
}

/// Hand-edit the memory. The whole point is that the user gets the last word.
///
/// The controller is owned by a [TextEditingScope], not by this function: the
/// sheet's future completes when the pop *begins*, so disposing it here would
/// pull the controller out from under a field that is still mounted and still
/// rebuilding as the keyboard slides away.
Future<void> showMemoryEditor(BuildContext context) async {
  final memory = context.read<MemoryProvider>();

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => TextEditingScope(
      text: memory.memory.text,
      builder: (sheetContext, controller) {
        final c = sheetContext.omColors;
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                Text('your memory', style: Theme.of(sheetContext).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'This is what Mynd carries into every conversation. Correct '
                  'anything that is wrong - your version wins.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.control),
                  ),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    maxLines: 8,
                    minLines: 5,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      hintText: 'e.g. You focus best late at night, and you are '
                          'working towards IELTS band 7.',
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Haptics.success();
                      memory.saveEdit(controller.text);
                      Navigator.of(sheetContext).pop();
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: c.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('save'),
                  ),
                ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// Everything the user parked mid-focus, so it is somewhere they can actually
/// go and find it again.
Future<void> showParkedThoughts(BuildContext context) {
  final memory = context.read<MemoryProvider>();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ChangeNotifierProvider.value(
      value: memory,
      child: Consumer<MemoryProvider>(
        builder: (ctx, m, _) {
          final c = ctx.omColors;
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('parked thoughts', style: Theme.of(ctx).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('the things you put down so you could keep going.',
                      style: Theme.of(ctx).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.lg),
                  if (m.parked.isEmpty)
                    Text('nothing parked right now.',
                        style: Theme.of(ctx).textTheme.bodySmall)
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: m.parked.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final t = m.parked[i];
                          return Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(AppRadius.control),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.text,
                                          style: Theme.of(ctx).textTheme.bodyLarge),
                                      const SizedBox(height: 4),
                                      Text(DateFormat.MMMd().add_jm().format(t.at),
                                          style: Theme.of(ctx)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(color: c.text2)),
                                    ],
                                  ),
                                ),
                                OmTappable(
                                  onTap: () {
                                    Haptics.light();
                                    m.removeThought(t.id);
                                  },
                                  feedback: OmTapFeedback.none,
                                  pressedScale: 0.85,
                                  child: Icon(OmIcons.byName('x'),
                                      size: 18, color: c.text2),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}
