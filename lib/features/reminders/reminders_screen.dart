import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_screen_header.dart';
import '../../widgets/om_switch.dart';
import '../../widgets/om_tappable.dart';
import '../../providers/task_provider.dart';

enum _Freq {
  daily('Daily', Color(0xFF5C9E72)),
  weekly('Weekly', Color(0xFF8A86A6)),
  monthly('Monthly', Color(0xFF2F6E8F)),
  once('Once', Color(0xFFE88A3D));

  const _Freq(this.label, this.color);
  final String label;
  final Color color;
}

class _Reminder {
  _Reminder({
    required this.title,
    required this.category,
    required this.freq,
    required this.when,
    this.enabled = true,
  });
  final String title;
  final String category;
  final _Freq freq;
  final String when;
  bool enabled;
}

/// "reminders" — gentle, categorised nudges with a clear cadence badge.
/// Mirrors the prototype's `#screen-reminders`.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _reminders = [
    _Reminder(title: 'Take Medication', category: 'Health & Wellness', freq: _Freq.daily, when: '8:00 AM'),
    _Reminder(title: 'Water Plants', category: 'Home Chores', freq: _Freq.weekly, when: 'Sat 10:00 AM', enabled: false),
    _Reminder(title: 'Pay Rent', category: 'Finances', freq: _Freq.monthly, when: '1st of Month'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheduledTasks = context.watch<TaskProvider>().daySchedule;
    final dynamicReminders = scheduledTasks.map((t) => _Reminder(
      title: t.title,
      category: t.energy.label,
      freq: _Freq.once,
      when: t.startTime != null ? DateFormat.jm().format(t.startTime!) : 'Today',
      enabled: true, // Auto-enabled for the day
    )).toList();

    final allReminders = [...dynamicReminders, ..._reminders];

    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH, AppSpacing.screenTop, AppSpacing.screenH, AppSpacing.screenBottom),
          children: [
            const OmScreenHeader(
              title: 'reminders',
              subtitle: 'things to remember, big or small.',
              filledBack: true,
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Icon(Icons.music_note_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Alarm Tone', style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                DropdownButton<String>(
                  value: settings.selectedRingtone,
                  underline: const SizedBox.shrink(),
                  items: ['Default', 'Chime', 'Beep'].map((t) => DropdownMenuItem(value: t, child: Text(t, style: Theme.of(context).textTheme.bodySmall))).toList(),
                  onChanged: (val) {
                    if (val != null) settings.setRingtone(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            for (final r in allReminders) ...[
              _ReminderCard(reminder: r, onToggle: (v) => setState(() => r.enabled = v)),
              const SizedBox(height: AppSpacing.md),
            ],
            _AddButton(onTap: () => Toast.show(context, 'New reminder')),
          ],
        ),
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({required this.reminder, required this.onToggle});

  final _Reminder reminder;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final on = reminder.enabled;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: on ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: on
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 18, offset: const Offset(0, 8))]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reminder.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(reminder.category,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _FreqBadge(freq: reminder.freq),
                      const SizedBox(width: 10),
                      Text(reminder.when,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            OmSwitch(value: on, onChanged: onToggle),
          ],
        ),
      ),
    );
  }
}

class _FreqBadge extends StatelessWidget {
  const _FreqBadge({required this.freq});

  final _Freq freq;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: freq.color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(freq.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: freq.color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              )),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      pressedScale: 0.97,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: c.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(OmIcons.byName('plus'), size: 18, color: c.text),
            const SizedBox(width: 8),
            Text('add a reminder',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
