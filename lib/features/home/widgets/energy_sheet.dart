import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:convert';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/groq_service.dart';
import '../../../core/services/speech_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/toast.dart';
import '../../../models/energy_level.dart';
import '../../../models/task.dart';
import '../../../providers/energy_provider.dart';
import '../../../providers/settings_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_button.dart';
import '../../../widgets/om_tappable.dart';
import '../../../widgets/text_editing_scope.dart';

/// Bottom sheet for logging current energy ("how's the vibe?"). Logging
/// "brain-dead" can auto-enable low-stim mode.
Future<void> showEnergyPicker(BuildContext context) async {
  final energyProvider = context.read<EnergyProvider>();
  final settings = context.read<SettingsProvider>();

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("how's the vibe right now?", style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('we’ll match your tasks to your energy.',
                  style: Theme.of(sheetContext).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.xl),
              for (final level in EnergyLevel.values) ...[
                _EnergyRow(
                  level: level,
                  onTap: () {
                    Haptics.select();
                    energyProvider.set(level);
                    settings.onEnergyLogged(isBrainDead: level == EnergyLevel.dead);
                    Navigator.of(sheetContext).pop();
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
        ),
      );
    },
  );
}

class _EnergyRow extends StatelessWidget {
  const _EnergyRow({required this.level, required this.onTap});

  final EnergyLevel level;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.omColors;
    final color = level.color(context);
    return OmTappable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(level.icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Text('${level.label} energy',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colors.text,
                      fontWeight: FontWeight.w600,
                    )),
            const Spacer(),
            Icon(OmIcons.byName('chevR'), color: color.withValues(alpha: 0.6), size: 18),
          ],
        ),
      ),
    );
  }
}

/// Quick "brain dump" sheet to add a task with an energy tag.
/// Rounds up to the next :00/:15/:30/:45 so generated blocks start on a clean
/// slot instead of an arbitrary 10:37.
DateTime _nextQuarterHour(DateTime t) {
  final base = DateTime(t.year, t.month, t.day, t.hour, t.minute);
  final add = 15 - (base.minute % 15);
  return base.add(Duration(minutes: add == 15 ? 0 : add));
}

Future<void> showQuickAddTask(BuildContext context) async {
  final tasks = context.read<TaskProvider>();
  var energy = EnergyLevel.high;
  var recording = false;
  var transcribing = false;

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
          builder: (context, setState) {
            void submit() {
              final text = controller.text.trim();
              if (text.isEmpty) return;

              // Pop immediately for instant feeling of offloading!
              Navigator.of(context).pop();
              Haptics.success();
              
              // Process AI in the background
              Toast.show(context, 'Processing brain dump...');
              
              Future.microtask(() async {
                try {
                  final prompt = '''
You are an ADHD task assistant. The user provided a brain dump: "$text".
Break this down into concise, actionable tasks. For each task, provide a title, an energy level (high, low, dead), an estimated duration in minutes, and optionally a list of micro-steps.
Keep durations realistic and ADHD-friendly: 15-45 minutes each.
Respond ONLY with a valid JSON array of objects. Do not wrap it in markdown. Format:
[
  {
    "title": "Task title",
    "energy": "high",
    "minutes": 30,
    "steps": ["Step 1", "Step 2"]
  }
]
''';
                  final response = await GroqService.instance.complete([
                    {'role': 'system', 'content': 'You are a JSON-only API. Only output valid JSON.'},
                    {'role': 'user', 'content': prompt},
                  ]);
                  
                  final cleaned = response.replaceAll('```json', '').replaceAll('```', '').trim();
                  final jsonArray = jsonDecode(cleaned) as List;
                  final newTasks = <Task>[];

                  // Lay the steps out back-to-back from the next quarter hour.
                  // Without a startTime a task is invisible to daySchedule, so
                  // an unscheduled breakdown never reaches the timeline at all -
                  // which reads as "the AI did nothing".
                  var cursor = _nextQuarterHour(DateTime.now());

                  for (final item in jsonArray) {
                    final map = item as Map<String, dynamic>;
                    final eStr = map['energy']?.toString().toLowerCase() ?? '';
                    final en = eStr.contains('high') ? EnergyLevel.high :
                               eStr.contains('low') ? EnergyLevel.low : EnergyLevel.dead;

                    final stepsJson = map['steps'] as List?;
                    final steps = stepsJson?.map((s) => MicroStep(text: s.toString())).toList();

                    final mins = (map['minutes'] as num?)?.clamp(5, 120).toInt() ?? 30;

                    newTasks.add(Task(
                      id: 'ai-${DateTime.now().microsecondsSinceEpoch}-${newTasks.length}',
                      title: map['title']?.toString() ?? 'Untitled',
                      time: 'today',
                      energy: en,
                      steps: steps,
                      scheduled: true,
                      startTime: cursor,
                      duration: Duration(minutes: mins),
                    ));

                    // A short breather between blocks, rounded to a clean slot.
                    cursor = _nextQuarterHour(cursor.add(Duration(minutes: mins + 5)));
                  }

                  if (newTasks.isNotEmpty) {
                    tasks.addTasks(newTasks);
                    Haptics.success();
                  } else {
                    tasks.addQuickTask(text, energy);
                  }
                } catch (e) {
                  // Still capture the thought - offloading it is the point - but
                  // say what went wrong. Swallowing this made a broken API key
                  // and a malformed response look identical to "AI is off".
                  debugPrint('[brain-dump] breakdown failed: $e');
                  tasks.addQuickTask(text, energy);
                  if (context.mounted) {
                    Toast.show(context, "Saved it, but couldn't break it down - $e");
                  }
                }
              });
            }

            // Voice brain dump: speak it, Groq Whisper transcribes, text drops
            // into the field so the user can review/edit before adding.
            Future<void> toggleMic() async {
              final stt = SpeechService.instance;
              if (recording) {
                setState(() {
                  recording = false;
                  transcribing = true;
                });
                String text = '';
                try {
                  text = await stt.stopAndTranscribe();
                } catch (_) {/* keep whatever's typed */}
                if (text.trim().isNotEmpty) {
                  final existing = controller.text.trim();
                  controller.text = existing.isEmpty ? text.trim() : '$existing ${text.trim()}';
                  controller.selection = TextSelection.collapsed(offset: controller.text.length);
                }
                Haptics.light();
                setState(() => transcribing = false);
              } else {
                Haptics.medium();
                setState(() => recording = true);
                final ok = await stt.startRecording();
                if (!ok) {
                  setState(() => recording = false);
                  if (context.mounted) {
                    Toast.show(context, 'Microphone unavailable');
                  }
                }
              }
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              Text('brain dump', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text("get it out of your head - we'll sort it later.",
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                cursorColor: colors.primary,
                style: Theme.of(context).textTheme.bodyLarge,
                onSubmitted: (_) => submit(),
                decoration: InputDecoration(
                  hintText: 'what needs doing?',
                  hintStyle: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: colors.text2),
                  filled: true,
                  fillColor: colors.surfaceAlt,
                  prefixIcon: Icon(OmIcons.byName('edit'), size: 19, color: colors.text2),
                  suffixIcon: OmTappable(
                    onTap: transcribing ? null : toggleMic,
                    feedback: OmTapFeedback.none,
                    pressedScale: 0.85,
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: transcribing
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: Padding(
                                padding: const EdgeInsets.all(2),
                                child: CircularProgressIndicator(strokeWidth: 2, color: colors.primary),
                              ),
                            )
                          : Icon(
                              recording ? OmIcons.byName('mic-off') : OmIcons.byName('mic'),
                              size: 24,
                              color: recording ? colors.error : colors.primary,
                            ),
                    ),
                  ),
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
              Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Text('how are you feeling right now?', style: Theme.of(context).textTheme.titleSmall),
            ),  const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  for (final level in EnergyLevel.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _EnergyPick(
                          level: level,
                          selected: energy == level,
                          onTap: () => setState(() => energy = level),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xl),
              OmButton(
                label: 'add it',
                icon: OmIcons.byName('plus'),
                onPressed: submit,
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

/// Selectable energy pill used in the brain-dump sheet - replaces the default
/// Material [ChoiceChip] with the app's softer, tappable style.
class _EnergyPick extends StatelessWidget {
  const _EnergyPick({required this.level, required this.selected, required this.onTap});

  final EnergyLevel level;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = level.color(context);
    return OmTappable(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : context.omColors.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(level.icon, size: 20, color: color),
            const SizedBox(height: 5),
            Text(
              level.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected ? context.omColors.text : context.omColors.text2,
                    fontWeight: FontWeight.w700,
                    fontSize: 11,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
