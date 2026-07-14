import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/groq_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/om_icons.dart';
import '../../../models/energy_level.dart';
import '../../../models/task.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_tappable.dart';

void showBrainDumpSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const BrainDumpSheet(),
  );
}

class BrainDumpSheet extends StatefulWidget {
  const BrainDumpSheet({super.key});

  @override
  State<BrainDumpSheet> createState() => _BrainDumpSheetState();
}

class _BrainDumpSheetState extends State<BrainDumpSheet> {
  final _controller = TextEditingController();
  bool _processing = false;

  Future<void> _process() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _processing = true);

    try {
      final response = await GroqService.instance.complete([
        {
          'role': 'system',
          'content': 'You are a task extraction assistant. The user will provide a messy brain dump. '
                     'Extract actionable tasks from the text. Respond ONLY with a valid JSON array of strings, '
                     'where each string is a concise task title. Do not include any other formatting, explanations, or markdown blocks.'
        },
        {'role': 'user', 'content': text},
      ]);

      // Clean markdown wrappers if any
      String cleaned = response.trim();
      if (cleaned.startsWith('```json')) cleaned = cleaned.substring(7);
      if (cleaned.startsWith('```')) cleaned = cleaned.substring(3);
      if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
      cleaned = cleaned.trim();

      final List<dynamic> parsed = jsonDecode(cleaned);
      final tasks = parsed.cast<String>();

      if (!mounted) return;

      final tp = context.read<TaskProvider>();
      final newTasks = tasks.map((title) => Task(
        id: 'bd_${DateTime.now().microsecondsSinceEpoch}_${title.hashCode}',
        title: title,
        time: 'today',
        energy: EnergyLevel.low,
      )).toList();
      
      tp.addTasks(newTasks);

      Navigator.of(context).pop();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${tasks.length} tasks to your backlog!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to process: $e')),
      );
    } finally {
      if (mounted) setState(() => _processing = false);
    }
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
            Text('Brain Dump', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Dump your messy thoughts. AI will break them into actionable tasks.', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _controller,
              maxLines: 5,
              minLines: 3,
              autofocus: true,
              style: Theme.of(context).textTheme.bodyLarge,
              decoration: InputDecoration(
                hintText: 'e.g., I need to buy milk, text mom, and finish the report by tomorrow...',
                hintStyle: TextStyle(color: c.text2.withValues(alpha: 0.5)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.primary, width: 2)),
                filled: true,
                fillColor: c.bg,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            OmTappable(
              onTap: _processing ? null : _process,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [c.primary, c.flow]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: c.primary.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                alignment: Alignment.center,
                child: _processing 
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(OmIcons.byName('sparkles'), color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          const Text('Process with AI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16)),
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
