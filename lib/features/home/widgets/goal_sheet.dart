import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/toast.dart';
import '../../../providers/energy_provider.dart';
import '../../../providers/goal_provider.dart';
import '../../../widgets/om_button.dart';
import '../../../widgets/om_form_page.dart';
import '../../../widgets/om_tappable.dart';
import '../../../widgets/om_time_picker.dart';
import '../../../widgets/text_editing_scope.dart';

/// A toast that does not need a live widget to show itself.
///
/// The plan is built after this page has closed, so by the time there is
/// something to report the context that started it is gone. A messenger caught
/// on the way in still works.
void _toast(ScaffoldMessengerState messenger, Color ink, String message) {
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 96),
        backgroundColor: ink,
      ),
    );
}

/// "New goal": capture a title, a target date ("achieve this by") and the slot
/// they are setting aside for it, then hand off to [GoalProvider] which breaks
/// the goal into a day-by-day plan tuned to the user's current energy.
///
/// A full screen, not a sheet. Four fields and a keyboard is more than a sheet
/// can hold without shoving itself off the top of the display.
Future<void> showAddGoalSheet(BuildContext context) async {
  final goals = context.read<GoalProvider>();
  final energy = context.read<EnergyProvider>().current;
  // Read once, here, while the caller is definitely alive.
  //
  // Everything inside this page used to reach back through the CALLER's
  // context - themes, the date picker, the toasts, the pop. That held only as
  // long as the caller outlived the page. It stopped holding the moment this
  // was opened from the nav bar's add sheet, which closes itself on the way in:
  // every later lookup was then a lookup on a deactivated widget, which is the
  // "looking up a deactivated widget's ancestor is unsafe" error, and it fired
  // on the first keystroke.
  //
  // The page's own context is used inside instead. This one is only for the
  // toasts that land AFTER the page is gone, and it is a messenger rather than
  // a context because a messenger keeps working when the widget that found it
  // does not.
  final messenger = ScaffoldMessenger.of(context);
  final toastInk = context.omColors.text;
  DateTime? targetDate;
  // The slot the user sets aside for this goal every day. A goal with no time
  // booked for it is a wish, so we ask up front rather than hoping
  // auto-schedule finds room.
  TimeOfDay? dailyStart;
  int dailyMinutes = 60;

  await showOmFormPage<void>(
    context,
    title: 'new goal',
    subtitle: "the big thing - we'll break it into daily steps.",
    builder: (sheetContext) {
      final colors = sheetContext.omColors;
      return TextEditingScope(
        builder: (scopeContext, controller) => Builder(
        builder: (_) => StatefulBuilder(
          builder: (builderContext, setState) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: builderContext,
                initialDate: targetDate ?? now.add(const Duration(days: 7)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
                helpText: 'Achieve this goal by',
              );
              if (picked != null) setState(() => targetDate = picked);
            }

            Future<void> pickSlot() async {
              final picked = await showOmTimePicker(
                context: builderContext,
                initialTime: dailyStart ?? const TimeOfDay(hour: 18, minute: 0),
                helpText: 'Work on this each day at',
              );
              if (picked != null) setState(() => dailyStart = picked);
            }

            void create() {
              final title = controller.text.trim();
              if (title.isEmpty) {
                Toast.show(builderContext, 'Give your goal a name first');
                return;
              }
              if (targetDate == null) {
                Toast.show(builderContext, 'Pick when you want to achieve it');
                return;
              }
              
              // Unfocus the TextField before popping to remove any active text 
              // selection overlays, avoiding a known Flutter framework bug where
              // the overlay unmounts incorrectly and crashes.
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(builderContext).pop();
              Haptics.success();
              _toast(messenger, toastInk, 'Breaking your goal into daily steps…');

              final date = targetDate!;
              final slot = dailyStart;
              final minutes = dailyMinutes;
              Future.microtask(() async {
                final err = await goals.addGoal(
                  title: title,
                  targetDate: date,
                  currentEnergy: energy,
                  dailyStart: slot,
                  dailyMinutes: minutes,
                );
                if (err != null) {
                  _toast(messenger, toastInk, err);
                } else {
                  Haptics.success();
                  _toast(messenger, toastInk,
                      'Goal plan ready - today’s step is on your timeline');
                }
              });
            }

            // The page scrolls for us now, and the title/subtitle live in its
            // header rather than being repeated here.
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  cursorColor: colors.primary,
                  style: Theme.of(builderContext).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'learn to play guitar',
                    hintStyle: Theme.of(builderContext).textTheme.bodyLarge?.copyWith(color: colors.text2),
                    filled: true,
                    fillColor: colors.surfaceAlt,
                    prefixIcon: Icon(OmIcons.byName('activity'), size: 19, color: colors.text2),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      borderSide: BorderSide(color: colors.primary, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('when do you want to achieve this by?', style: Theme.of(builderContext).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.sm),
                OmTappable(
                  onTap: pickDate,
                  pressedScale: 0.98,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(
                        color: targetDate == null ? colors.border : colors.primary,
                        width: targetDate == null ? 1 : 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(OmIcons.byName('calendar'), size: 18, color: colors.text2),
                        const SizedBox(width: 12),
                        Text(
                          targetDate == null
                              ? 'pick a target date'
                              : DateFormat('EEE, MMM d, yyyy').format(targetDate!),
                          style: Theme.of(builderContext).textTheme.bodyLarge?.copyWith(
                                color: targetDate == null ? colors.text2 : colors.text,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('which part of the day is this goal’s?',
                    style: Theme.of(builderContext).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text('today’s step gets booked here, every day, until the deadline.',
                    style: Theme.of(builderContext).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                OmTappable(
                  onTap: pickSlot,
                  pressedScale: 0.98,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    decoration: BoxDecoration(
                      color: colors.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border: Border.all(
                        color: dailyStart == null ? colors.border : colors.primary,
                        width: dailyStart == null ? 1 : 2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(OmIcons.byName('clock'), size: 18, color: colors.text2),
                        const SizedBox(width: 12),
                        Text(
                          dailyStart == null
                              ? 'pick a daily time'
                              : dailyStart!.format(builderContext),
                          style: Theme.of(builderContext).textTheme.bodyLarge?.copyWith(
                                color: dailyStart == null ? colors.text2 : colors.text,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('how long each day?', style: Theme.of(builderContext).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.sm),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in const [30, 45, 60, 90, 120, 180])
                      ChoiceChip(
                        selected: dailyMinutes == m,
                        label: Text(m >= 60
                            ? '${m ~/ 60}h${m % 60 == 0 ? '' : ' ${m % 60}m'}'
                            : '${m}m'),
                        onSelected: (_) => setState(() => dailyMinutes = m),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                OmButton(
                  label: 'create plan',
                  icon: OmIcons.byName('plus'),
                  onPressed: create,
                ),
              ],
            );
          },
        ),
      ),
      );
    },
  );
}
