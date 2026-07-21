import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/api_config.dart';
import '../../core/services/memory_snapshot.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../providers/coach_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/energy_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/habit_provider.dart';
import '../../providers/memory_provider.dart';
import '../../providers/mood_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_tappable.dart';
import '../../widgets/text_editing_scope.dart';

/// The things you can do to the memory, wherever you are standing.
///
/// These used to hang off a card on Home. The card is gone: the memory has its
/// own screen in Settings now, and a profile of you is something you go and
/// read, not something that greets you every morning on the way to your day.
/// The behaviour outlived the widget, so it lives here instead.

/// Rewrite the memory from everything the app can currently see.
///
/// Shared by the refresh button on the memory screen and by the
/// [MemoryAutopilot], so both read from exactly the same picture of the user.
/// [quiet] suppresses the failure toast: an automatic pass failing is not news
/// the user asked for, and the previous memory is still there.
Future<void> refreshMemory(BuildContext context,
    {bool haptic = true, bool quiet = false}) async {
  if (haptic) Haptics.medium();
  final memory = context.read<MemoryProvider>();
  await memory.refresh(snapshotOf(context));
  if (!quiet && context.mounted && memory.error != null) {
    Toast.show(context, memory.error!);
  }
}

/// Everything the app can currently see about the user, as prose.
///
/// Assembled here rather than in a provider because only the widget tree has
/// all the other providers to hand. Shared by the memory and by the mood
/// reading, deliberately: two different claims about the same person should
/// not be drawn from two different pictures of them.
String snapshotOf(BuildContext context) {
  final memory = context.read<MemoryProvider>();
  return buildMemorySnapshot(
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
}

/// Ask the model how this person seems to be doing.
///
/// Given the same picture as the memory, plus the memory itself and the
/// thoughts they parked mid-focus - which are the highest-signal thing in the
/// app, because a thought worth interrupting yourself over is rarely a small
/// one. Failures are silent: nobody asked for this, and a stale reading beats
/// an error about a reading.
Future<void> readMood(BuildContext context) async {
  final memory = context.read<MemoryProvider>();
  final mood = context.read<MoodProvider>();
  final parked = memory.parked.isEmpty
      ? ''
      : memory.parked.take(12).map((t) => '- ${t.text}').join('\n');
  await mood.predict(
    snapshotOf(context),
    memory: memory.memory.text,
    parked: parked,
  );
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
