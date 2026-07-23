import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../models/energy_level.dart';
import '../../../models/task.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_chip.dart';
import '../../../widgets/om_tappable.dart';

void showEditTaskSheet(BuildContext context, Task task) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => EditTaskSheet(task: task),
  );
}

class EditTaskSheet extends StatefulWidget {
  const EditTaskSheet({super.key, required this.task});
  final Task task;

  @override
  State<EditTaskSheet> createState() => _EditTaskSheetState();
}

class _EditTaskSheetState extends State<EditTaskSheet> {
  late final TextEditingController _controller;
  late EnergyLevel _energy;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
    _energy = widget.task.energy;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final newTitle = _controller.text.trim();
    if (newTitle.isNotEmpty) {
      context.read<TaskProvider>().editTask(widget.task.id, newTitle, _energy);
    }
    Navigator.of(context).pop();
  }

  void _delete() {
    context.read<TaskProvider>().deleteTask(widget.task.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xl),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit Task', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              autofocus: true,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                labelText: 'Task Title',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.primary, width: 2)),
                filled: true,
                fillColor: c.bg,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Priority / Energy Required', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final e in [EnergyLevel.high, EnergyLevel.low, EnergyLevel.dead])
                  OmChip(
                    label: e.label,
                    icon: e.icon,
                    selected: _energy == e,
                    onTap: () => setState(() => _energy = e),
                  )
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            OmTappable(
              onTap: _save,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: c.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                alignment: Alignment.center,
                child: const Text('Save Changes', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            // "I'm never doing this": remove the task outright, distinct from
            // scheduling or ticking it off.
            OmTappable(
              onTap: _delete,
              feedback: OmTapFeedback.light,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 18, color: c.error),
                    const SizedBox(width: 6),
                    Text('Delete task',
                        style: TextStyle(color: c.error, fontWeight: FontWeight.w700, fontSize: 15)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
