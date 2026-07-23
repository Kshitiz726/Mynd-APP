import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/reminder.dart';
import '../../providers/reminders_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/om_screen_header.dart';
import '../../widgets/om_switch.dart';
import '../../widgets/om_tappable.dart';
import '../../widgets/om_time_picker.dart';

/// "reminders" - the things you asked to be told about, and the promise that
/// you will actually be told.
///
/// Everything on this screen is now real: the list is persisted, a toggle
/// arms or disarms an actual OS notification, and today's timed blocks get a
/// quiet nudge unless you turn that one off. Before, the list was three
/// hardcoded examples and the switches did nothing at all.
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  bool? _notificationsOn;

  @override
  void initState() {
    super.initState();
    _checkPermission();
  }

  Future<void> _checkPermission() async {
    final on = await NotificationService.instance.enabled;
    if (mounted) setState(() => _notificationsOn = on);
  }

  Future<void> _enableNotifications() async {
    Haptics.medium();
    final granted = await NotificationService.instance.requestPermissions();
    if (!mounted) return;
    setState(() => _notificationsOn = granted);
    if (granted) {
      await context.read<RemindersProvider>().resync();
      if (mounted) Toast.show(context, 'reminders will arrive now.');
    } else if (mounted) {
      Toast.show(context, 'still off. android settings can turn them back on.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reminders = context.watch<RemindersProvider>();
    final tasks = context.watch<TaskProvider>().daySchedule
        .where((t) => t.startTime != null && !t.done)
        .toList();
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
              AppSpacing.screenTop, AppSpacing.screenH, AppSpacing.screenBottom),
          children: [
            const OmScreenHeader(
              title: 'reminders',
              subtitle: 'things to remember, big or small.',
            ),
            const SizedBox(height: AppSpacing.md),
            if (_notificationsOn == false)
              _PermissionCard(onEnable: _enableNotifications),
            Row(
              children: [
                Icon(Icons.music_note_rounded,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('Alarm Tone',
                    style: Theme.of(context).textTheme.titleSmall),
                const Spacer(),
                DropdownButton<String>(
                  value: settings.selectedRingtone,
                  underline: const SizedBox.shrink(),
                  items: ['Default', 'Chime', 'Beep']
                      .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t,
                              style: Theme.of(context).textTheme.bodySmall)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) settings.setRingtone(val);
                  },
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            // Whether notifications actually work on a given phone is not
            // something anyone should have to discover by missing one.
            OmTappable(
              onTap: () async {
                Haptics.light();
                await NotificationService.instance.showNow(
                  id: 424242,
                  title: 'this is what a reminder looks like',
                  body: 'if you can see this, they are working.',
                );
                if (context.mounted) Toast.show(context, 'sent one just now.');
              },
              feedback: OmTapFeedback.none,
              pressedScale: 0.98,
              child: Row(
                children: [
                  Icon(OmIcons.byName('alarm'),
                      size: 15, color: context.omColors.primary),
                  const SizedBox(width: 8),
                  Text('send a test notification',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: context.omColors.primary,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (reminders.reminders.isEmpty && tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'nothing set. add one and it will find you, even with the '
                  'app closed.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: context.omColors.text2),
                ),
              ),
            for (final r in reminders.reminders) ...[
              _ReminderCard(
                title: r.title,
                subtitle: r.note.isEmpty ? 'reminder' : r.note,
                badge: r.repeat.label,
                badgeColor: r.repeat == ReminderRepeat.daily
                    ? const Color(0xFF5C9E72)
                    : const Color(0xFFE88A3D),
                when: _clock(r.hour, r.minute),
                enabled: r.enabled,
                onToggle: (v) {
                  Haptics.select();
                  context.read<RemindersProvider>().setEnabled(r.id, v);
                },
                onTap: () => _edit(context, existing: r),
                onDelete: () {
                  Haptics.light();
                  context.read<RemindersProvider>().remove(r.id);
                },
              ),
              const SizedBox(height: AppSpacing.md),
            ],
            if (tasks.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text('today\'s blocks',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              for (final t in tasks) ...[
                _ReminderCard(
                  title: t.title,
                  subtitle: t.energy.label,
                  badge: 'Once',
                  badgeColor: const Color(0xFFE88A3D),
                  when: DateFormat.jm().format(t.startTime!),
                  enabled: !reminders.isTaskMuted(t.id),
                  onToggle: (v) {
                    Haptics.select();
                    context.read<RemindersProvider>().setTaskNudge(t.id, v);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ],
            _AddButton(onTap: () => _edit(context)),
          ],
        ),
      ),
    );
  }

  static String _clock(int h, int m) =>
      DateFormat.jm().format(DateTime(2000, 1, 1, h, m));

  Future<void> _edit(BuildContext context, {Reminder? existing}) async {
    Haptics.light();
    final saved = await showModalBottomSheet<Reminder>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReminderSheet(existing: existing),
    );
    if (saved == null || !context.mounted) return;
    final provider = context.read<RemindersProvider>();
    if (existing == null) {
      await provider.add(saved);
    } else {
      await provider.update(saved);
    }
    if (!context.mounted) return;
    // Permission may never have been asked for if they skipped it at launch.
    if (!await NotificationService.instance.enabled) {
      if (context.mounted) await _enableNotifications();
    }
  }
}

/// Shown only when the OS says notifications are off, because a reminders
/// screen that quietly cannot remind you is the worst version of this feature.
class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: c.attention.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('notifications are off',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'nothing here can reach you until android is allowed to show them.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: c.text2),
          ),
          const SizedBox(height: 12),
          OmTappable(
            onTap: onEnable,
            feedback: OmTapFeedback.none,
            pressedScale: 0.97,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                gradient: c.brandGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text('turn them on',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReminderCard extends StatelessWidget {
  const _ReminderCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.when,
    required this.enabled,
    required this.onToggle,
    this.onTap,
    this.onDelete,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final String when;
  final bool enabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final card = AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: enabled ? 1 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: enabled
              ? [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 8))
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: c.text2, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _Badge(label: badge, color: badgeColor),
                      const SizedBox(width: 10),
                      Text(when,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ],
              ),
            ),
            OmSwitch(value: enabled, onChanged: onToggle),
          ],
        ),
      ),
    );

    final tappable = onTap == null
        ? card
        : OmTappable(
            onTap: onTap!,
            feedback: OmTapFeedback.none,
            pressedScale: 0.99,
            child: card);

    if (onDelete == null) return tappable;
    return Dismissible(
      key: ValueKey('rem-$title-$when'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete!(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: c.error.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Icon(OmIcons.byName('trash'), size: 18, color: c.error),
      ),
      child: tappable,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 11,
              )),
    );
  }
}

/// Add or edit one reminder: what, when, and whether it comes back tomorrow.
class _ReminderSheet extends StatefulWidget {
  const _ReminderSheet({this.existing});

  final Reminder? existing;

  @override
  State<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends State<_ReminderSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.existing?.title ?? '');
  late TimeOfDay _time = widget.existing == null
      ? TimeOfDay.now().replacing(minute: 0)
      : TimeOfDay(hour: widget.existing!.hour, minute: widget.existing!.minute);
  late ReminderRepeat _repeat = widget.existing?.repeat ?? ReminderRepeat.once;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  void _save() {
    final t = _title.text.trim();
    if (t.isEmpty) return;
    Haptics.success();
    final base = widget.existing;
    Navigator.of(context).pop(
      base == null
          ? Reminder(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              title: t,
              hour: _time.hour,
              minute: _time.minute,
              repeat: _repeat,
            )
          : base.copyWith(
              title: t,
              hour: _time.hour,
              minute: _time.minute,
              repeat: _repeat,
              enabled: true,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.existing == null ? 'new reminder' : 'edit reminder',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text('it will arrive whether the app is open or not.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: TextField(
                  controller: _title,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _save(),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: 'what should I remind you about?',
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: OmTappable(
                      onTap: () async {
                        final picked = await showOmTimePicker(
                            context: context, initialTime: _time);
                        if (picked != null) setState(() => _time = picked);
                      },
                      feedback: OmTapFeedback.none,
                      pressedScale: 0.98,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius:
                              BorderRadius.circular(AppRadius.control),
                        ),
                        child: Row(
                          children: [
                            Icon(OmIcons.byName('clock'),
                                size: 16, color: c.text2),
                            const SizedBox(width: 10),
                            Text(_time.format(context),
                                style:
                                    Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  for (final r in ReminderRepeat.values)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: OmTappable(
                        onTap: () {
                          Haptics.select();
                          setState(() => _repeat = r);
                        },
                        feedback: OmTapFeedback.none,
                        pressedScale: 0.94,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: _repeat == r ? c.primaryTint : c.surfaceAlt,
                            borderRadius:
                                BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                                color:
                                    _repeat == r ? c.primary : Colors.transparent),
                          ),
                          child: Text(r.label,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(
                                    color: _repeat == r ? c.primary : c.text2,
                                    fontWeight: FontWeight.w700,
                                  )),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: c.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(widget.existing == null ? 'set it' : 'save'),
                ),
              ),
            ],
          ),
        ),
      ),
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
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
