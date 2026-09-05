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

/// Sends a brain dump to Groq, parses the task titles it returns, and adds them
/// to the backlog. Returns how many tasks were added; throws on failure.
///
/// Shared by the typed [BrainDumpSheet] and the voice capture flow so speaking
/// a dump and typing one break down into the exact same scheduled tasks.
Future<int> processBrainDumpText(String text, TaskProvider tp) async {
  final response = await GroqService.instance.extract([
    {
      'role': 'system',
      'content':
          'You are a task extraction assistant. The user will provide a messy brain dump. '
              'Extract every distinct actionable task from the text - do not cap or drop any. '
              'Only merge two items when they are literally the same action stated twice; '
              'otherwise keep them separate so nothing the user said is lost. '
              'Respond ONLY with a valid JSON array of strings, '
              'where each string is a concise task title. Do not include any other formatting, explanations, or markdown blocks.'
    },
    {'role': 'user', 'content': text},
  ]);

  // Clean markdown wrappers if any.
  String cleaned = response.trim();
  if (cleaned.startsWith('```json')) cleaned = cleaned.substring(7);
  if (cleaned.startsWith('```')) cleaned = cleaned.substring(3);
  if (cleaned.endsWith('```')) cleaned = cleaned.substring(0, cleaned.length - 3);
  cleaned = cleaned.trim();

  final List<dynamic> parsed = jsonDecode(cleaned);
  // No cap: every task the user spoke or typed should land. We only drop blanks.
  final titles =
      parsed.cast<String>().where((t) => t.trim().isNotEmpty).toList();

  final newTasks = titles
      .map((title) => Task(
            id: 'bd_${DateTime.now().microsecondsSinceEpoch}_${title.hashCode}',
            title: title,
            time: 'today',
            energy: EnergyLevel.low,
          ))
      .toList();

  tp.addTasks(newTasks);
  return newTasks.length;
}

/// Why a brain dump failed, in words a person can act on.
///
/// Shared by the typed sheet and the voice sheet, which used to swallow the
/// exception entirely and say "could not break that down" whether the session
/// had expired, the request had timed out, or the server had no key. Those need
/// different things from the user, so they say different things to them.
String brainDumpError(Object e) => switch (e) {
      CoachLimitException() =>
        'That hit the daily coach limit, which it should not - please report this.',
      GroqException(statusCode: 401) => 'Your session expired. Sign in again.',
      GroqException(statusCode: 408) =>
        'That took too long. Check your connection and try again.',
      GroqException(statusCode: 502) =>
        'The model had nothing to say about that. Try rephrasing it.',
      GroqException(statusCode: 503) =>
        'The server is not set up for this yet.',
      GroqException() => 'Could not reach the server. Try again in a moment.',
      FormatException() => 'That came back garbled. Give it another go.',
      _ => 'Could not read that. Try again.',
    };

class BrainDumpSheet extends StatefulWidget {
  const BrainDumpSheet({super.key});

  @override
  State<BrainDumpSheet> createState() => _BrainDumpSheetState();
}

class _BrainDumpSheetState extends State<BrainDumpSheet> {
  final _controller = TextEditingController();
  bool _processing = false;

  /// Why the last attempt failed, shown inside the sheet.
  ///
  /// This used to be a SnackBar, which is drawn at the bottom of the Scaffold -
  /// underneath the sheet that is still covering it. So a failed brain dump
  /// spun, stopped, and said nothing at all: the button looked broken rather
  /// than the request looking failed. The message has to appear on the surface
  /// the user is actually looking at.
  String? _error;

  Future<void> _process() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _processing = true;
      _error = null;
    });
    final tp = context.read<TaskProvider>();
    // Captured while this sheet is still mounted. The success path pops first,
    // and reaching back through a popped route's context for its messenger is
    // the same "deactivated widget's ancestor" fault the goal form had.
    final messenger = ScaffoldMessenger.of(context);

    try {
      final count = await processBrainDumpText(text, tp);
      if (!mounted) return;
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Added $count tasks to your backlog!')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = brainDumpError(e));
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
                hintText: 'I need to buy milk, text mom, and finish the report by tomorrow...',
                hintStyle: TextStyle(color: c.text2.withValues(alpha: 0.5)),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.border)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: c.primary, width: 2)),
                filled: true,
                fillColor: c.bg,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(OmIcons.byName('x'), size: 16, color: c.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: c.error, height: 1.3),
                    ),
                  ),
                ],
              ),
            ],
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
