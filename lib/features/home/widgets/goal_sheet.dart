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
import '../../../widgets/om_tappable.dart';
import '../../../widgets/text_editing_scope.dart';

/// "New goal" sheet: capture a title and a target date ("achieve this by"),
/// then hand off to [GoalProvider] which breaks the goal into a day-by-day plan
/// tuned to the user's current energy.
Future<void> showAddGoalSheet(BuildContext context) async {
  final goals = context.read<GoalProvider>();
  final energy = context.read<EnergyProvider>().current;
  DateTime? targetDate;

  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final colors = sheetContext.omColors;
      return TextEditingScope(
        builder: (scopeContext, controller) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 4,
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (builderContext, setState) {
            Future<void> pickDate() async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: targetDate ?? now.add(const Duration(days: 7)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
                helpText: 'Achieve this goal by',
              );
              if (picked != null) setState(() => targetDate = picked);
            }

            void create() {
              final title = controller.text.trim();
              if (title.isEmpty) {
                Toast.show(context, 'Give your goal a name first');
                return;
              }
              if (targetDate == null) {
                Toast.show(context, 'Pick when you want to achieve it');
                return;
              }
              
              // Unfocus the TextField before popping to remove any active text 
              // selection overlays, avoiding a known Flutter framework bug where
              // the overlay unmounts incorrectly and crashes.
              FocusManager.instance.primaryFocus?.unfocus();
              Navigator.of(context).pop();
              Haptics.success();
              Toast.show(context, 'Breaking your goal into daily steps…');

              final date = targetDate!;
              Future.microtask(() async {
                final err = await goals.addGoal(
                    title: title, targetDate: date, currentEnergy: energy);
                // ignore: use_build_context_synchronously
                if (!context.mounted) return;
                if (err != null) {
                  Toast.show(context, err);
                } else {
                  Haptics.success();
                  Toast.show(context, 'Goal plan ready - today’s step is on your timeline');
                }
              });
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('new goal', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text("the big thing - we'll break it into daily steps.",
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  cursorColor: colors.primary,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: 'e.g. learn to play guitar',
                    hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(color: colors.text2),
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
                Text('when do you want to achieve this by?', style: Theme.of(context).textTheme.titleSmall),
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
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: targetDate == null ? colors.text2 : colors.text,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ],
                    ),
                  ),
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
