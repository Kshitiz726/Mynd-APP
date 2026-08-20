import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../providers/memory_provider.dart';
import '../../widgets/text_editing_scope.dart';

/// "park a thought" - somewhere to put the intrusive thought so it stops
/// interrupting, without ending the session.
///
/// It has to be *fast*: one field, one button, keyboard already up. Anything
/// slower and the thought wins. What is parked lands in the user's memory, so
/// the coach can pick it up later and the user can find it on Home.
///
/// The controller belongs to a [TextEditingScope] so it outlives the sheet's
/// closing animation - disposing it when the future completes would kill a
/// field that is still rebuilding as the keyboard slides away.
Future<void> showParkThoughtSheet(BuildContext context) {
  final memory = context.read<MemoryProvider>();

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => TextEditingScope(
      builder: (sheetContext, controller) {
        final c = sheetContext.omColors;

        void save() {
          final text = controller.text.trim();
          if (text.isEmpty) return;
          Haptics.success();
          memory.parkThought(text);
          Navigator.of(sheetContext).pop();
          Toast.show(context, "Parked. It'll be waiting on Home.");
        }

        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('park it', style: Theme.of(sheetContext).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('Put it down here and get back to what you were doing.',
                      style: Theme.of(sheetContext).textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      maxLines: 3,
                      minLines: 1,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => save(),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        hintText: 'what just popped into your head?',
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: save,
                      style: FilledButton.styleFrom(
                        backgroundColor: c.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      ),
                      child: const Text('park it'),
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
