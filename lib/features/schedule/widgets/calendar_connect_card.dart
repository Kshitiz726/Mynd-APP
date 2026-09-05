import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/toast.dart';
import '../../../providers/calendar_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_tappable.dart';

/// Connecting the phone's calendar, and saying plainly what that does.
///
/// Two sentences rather than a toggle labelled "sync", because the two
/// directions are not the same promise and people are right to want to know
/// which one they are agreeing to: the app reads meetings so it stops planning
/// over them, and writes the blocks planned here into one calendar they pick.
class CalendarConnectCard extends StatefulWidget {
  const CalendarConnectCard({super.key});

  @override
  State<CalendarConnectCard> createState() => _CalendarConnectCardState();
}

class _CalendarConnectCardState extends State<CalendarConnectCard> {
  @override
  void initState() {
    super.initState();
    // After the first frame: connecting can raise the OS permission sheet, and
    // one landing on a half-built screen looks like a crash.
    WidgetsBinding.instance.addPostFrameCallback((_) => _pullDay());
  }

  /// Mirror the phone's events for the day being looked at into the timeline.
  Future<void> _pullDay() async {
    if (!mounted) return;
    final cal = context.read<CalendarProvider>();
    final tasks = context.read<TaskProvider>();
    final day = tasks.selectedDate;
    final imported = await cal.importDay(day);
    if (!mounted) return;
    tasks.mergeCalendar(imported, day);
  }

  Future<void> _connect() async {
    Haptics.light();
    final cal = context.read<CalendarProvider>();
    final ok = await cal.requestAccess();
    if (!mounted) return;
    if (!ok) {
      // Said out loud, because a denied permission otherwise looks exactly
      // like a phone with no calendars on it.
      Toast.show(context, 'calendar access was refused - allow it in Settings');
      return;
    }
    final writable = cal.writable;
    if (writable.isEmpty) {
      Toast.show(context, 'no calendar on this phone can be written to');
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.omColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _CalendarPicker(
        onPick: (id) async {
          Navigator.of(ctx).pop();
          await cal.connect(id);
          await _pullDay();
          if (mounted) Toast.show(context, 'calendar connected');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final cal = context.watch<CalendarProvider>();

    // Once connected this stops being a prompt and becomes a status line: one
    // row, a switch, and nothing to press by accident. The full invitation sat
    // at the top of the day every single time the tab was opened, which is a
    // sales pitch for something already bought.
    if (cal.connected || cal.hasAccess) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(
                cal.connected ? LucideIcons.calendarCheck : LucideIcons.calendar,
                size: 16,
                color: cal.connected ? c.primary : c.text2,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  cal.connected
                      ? 'calendar connected'
                      : 'calendar sync is off',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: cal.connected ? c.text : c.text2,
                  ),
                ),
              ),
              Switch.adaptive(
                value: cal.connected,
                activeThumbColor: c.primary,
                onChanged: (on) async {
                  Haptics.light();
                  if (!on) {
                    await cal.disconnect();
                    return;
                  }
                  // Turning it back on reuses the calendar already chosen,
                  // rather than asking again: the choice was made once and
                  // re-asking every time reads as the app having forgotten.
                  final id = cal.calendarId;
                  if (id != null) {
                    await cal.connect(id);
                    await _pullDay();
                  } else {
                    await _connect();
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return _Invite(onTap: _connect, busy: cal.busy);
  }
}

/// The one-time invitation, shown only while nothing is connected.
class _Invite extends StatelessWidget {
  const _Invite({required this.onTap, required this.busy});

  final VoidCallback onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none,
        pressedScale: 0.99,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(LucideIcons.calendarPlus, size: 19, color: c.text2),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('connect your calendar',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: c.text)),
                    const SizedBox(height: 3),
                    Text('so nothing gets planned on top of a meeting',
                        style: TextStyle(
                            fontSize: 12.5, height: 1.3, color: c.text2)),
                  ],
                ),
              ),
              if (busy)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.primary),
                )
              else
                Icon(LucideIcons.chevronRight, size: 17, color: c.text2),
            ],
          ),
        ),
      ),
    );
  }
}

/// Which calendar the app writes into.
///
/// Asked rather than assumed. The OS default is often a shared work calendar,
/// and quietly writing somebody's personal to-do list into one their colleagues
/// can see is the kind of mistake that cannot be taken back.
class _CalendarPicker extends StatelessWidget {
  const _CalendarPicker({required this.onPick});

  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final cals = context.watch<CalendarProvider>().writable;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('which calendar should plans go to?',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'reading works across all of them. this is only where blocks you '
              'plan here get written.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.lg),
            for (final cal in cals)
              OmTappable(
                onTap: () {
                  Haptics.light();
                  final id = cal.id;
                  if (id != null) onPick(id);
                },
                feedback: OmTapFeedback.none,
                pressedScale: 0.98,
                child: Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: cal.color == null
                              ? c.primary
                              : Color(cal.color!),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          cal.name ?? 'Calendar',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: c.text),
                        ),
                      ),
                      // Named, because "iCloud" and "Google" calendars can
                      // carry the same name and picking the wrong one is only
                      // discovered when the events turn up somewhere else.
                      if (cal.accountName != null)
                        Text(
                          cal.accountName!,
                          style: TextStyle(fontSize: 11.5, color: c.text2),
                        ),
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
