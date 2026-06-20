import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../features/alarms/alarm_wake_screen.dart';
import '../../main.dart';
import '../../providers/alarms_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/task_provider.dart';
import 'package:provider/provider.dart';
class AlarmService {
  AlarmService._();
  static final AlarmService instance = AlarmService._();

  final AudioPlayer _player = AudioPlayer();
  Timer? _tickTimer;
  bool _isPlaying = false;

  final Set<String> _triggeredIds = {};

  void init() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), _onTick);
  }

  void _onTick(Timer timer) {
    // Only check if we have a context to look up providers
    final ctx = rootNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;

    final now = DateTime.now();
    final hour = now.hour.toString();
    final minute = now.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';
    final minuteKey = '${now.year}${now.month}${now.day}_$timeStr';

    // 1. Check Alarms
    final alarms = ctx.read<AlarmsProvider>().alarms;
    for (final a in alarms) {
      if (a.enabled && a.time == timeStr) {
        final triggerId = 'alarm_${a.id}_$minuteKey';
        if (!_triggeredIds.contains(triggerId)) {
          _triggeredIds.add(triggerId);
          AlarmWakeScreen.open(ctx, a.time, a.ringtone);
          if (a.repeat == 'once') {
            ctx.read<AlarmsProvider>().toggleEnabled(a.id, false);
          }
        }
      }
    }

    // 2. Check Reminders (Tasks)
    final tasks = ctx.read<TaskProvider>().daySchedule;
    for (final t in tasks) {
      if (t.startTime != null && !t.done) {
        final st = t.startTime!;
        if (st.hour == now.hour && st.minute == now.minute) {
          final triggerId = 'task_${t.id}_$minuteKey';
          if (!_triggeredIds.contains(triggerId)) {
            _triggeredIds.add(triggerId);
            AlarmWakeScreen.open(ctx, t.title, 'Chime');
          }
        }
      }
    }
  }

  Future<void> playPreview(String ringtoneName) async {
    await stop();
    String path = 'audio/chime.mp3'; // Default fallback
    if (ringtoneName.toLowerCase() == 'beep') {
      path = 'audio/beep.mp3';
    } else if (ringtoneName.toLowerCase() == 'chime') {
      path = 'audio/chime.mp3';
    }
    
    _isPlaying = true;
    try {
      await _player.play(AssetSource(path));
    } catch (_) {
      // In case assets aren't bundled yet.
    }
  }

  Future<void> playLoop(String ringtoneName) async {
    await stop();
    String path = 'audio/chime.mp3';
    if (ringtoneName.toLowerCase() == 'beep') {
      path = 'audio/beep.mp3';
    }
    
    _isPlaying = true;
    _player.setReleaseMode(ReleaseMode.loop);
    try {
      await _player.play(AssetSource(path));
    } catch (_) {}
  }

  Future<void> stop() async {
    if (_isPlaying) {
      await _player.stop();
      _isPlaying = false;
    }
  }

  void dispose() {
    _tickTimer?.cancel();
    _player.dispose();
  }
}
