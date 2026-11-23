import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/alarm_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../widgets/om_tappable.dart';
import 'package:provider/provider.dart';
import '../../models/alarm.dart';
import '../../providers/alarms_provider.dart';
class AlarmWakeScreen extends StatefulWidget {
  const AlarmWakeScreen({super.key, required this.time, required this.ringtone});

  final String time;
  final String ringtone;

  static Future<void> open(BuildContext context, String time, String ringtone) {
    Haptics.medium();
    AlarmService.instance.playLoop(ringtone);
    return Navigator.of(context).push(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 360),
      reverseTransitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (_, __, ___) => AlarmWakeScreen(time: time, ringtone: ringtone),
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween(begin: 0.92, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    ));
  }

  @override
  State<AlarmWakeScreen> createState() => _AlarmWakeScreenState();
}

class _AlarmWakeScreenState extends State<AlarmWakeScreen> {
  void _dismiss() {
    AlarmService.instance.stop();
    Haptics.success();
    Navigator.of(context).maybePop();
    Toast.show(context, 'Alarm off - good morning.');
  }

  void _snooze() {
    AlarmService.instance.stop();
    Haptics.medium();
    
    // Add a snooze alarm for 10 minutes from now
    final snoozeTime = DateTime.now().add(const Duration(minutes: 10));
    final hour = snoozeTime.hour.toString();
    final minute = snoozeTime.minute.toString().padLeft(2, '0');
    final snoozeAlarm = Alarm(
      id: 'snooze_${DateTime.now().millisecondsSinceEpoch}',
      time: '$hour:$minute',
      label: 'Snooze',
      repeat: 'once',
      ringtone: widget.ringtone,
    );
    context.read<AlarmsProvider>().addAlarm(snoozeAlarm);

    Navigator.of(context).maybePop();
    Toast.show(context, 'Snoozed for 10 minutes.');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final dark = context.isDark;
    final gradient = dark
        ? [const Color(0xFF3A2A22), const Color(0xFF2A1E1C)]
        : [const Color(0xFFF4DBBA), const Color(0xFFE9B9A2)];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sheet),
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: gradient),
              ),
              child: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(OmIcons.byName('alarm'), size: 30, color: c.text),
                      const SizedBox(height: 14),
                      Text(widget.time,
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                                fontSize: 52,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1,
                                color: c.text,
                              )),
                      const SizedBox(height: 6),
                      Text('Morning! Time to wake up.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
                      const SizedBox(height: AppSpacing.xl),
                      
                      OmTappable(
                        pressedScale: 0.95,
                        onTap: _dismiss,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: c.primary,
                            borderRadius: BorderRadius.circular(AppRadius.control),
                          ),
                          child: Text('Stop',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                      color: OmColors.onFill(c.primary),
                                      fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      OmTappable(
                        feedback: OmTapFeedback.light,
                        onTap: _snooze,
                        child: Text('snooze (10m)',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: c.text2,
                                  decoration: TextDecoration.underline,
                                  fontWeight: FontWeight.w600,
                                )),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
