import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final Map<int, Timer> _scheduledTimers = {};
  final AudioPlayer _audioPlayer = AudioPlayer();

  Future<void> init() async {
    // No initialization needed for foreground audio
  }

  Future<void> scheduleAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? ringtone,
  }) async {
    // Cancel existing timer for this ID if any
    _scheduledTimers[id]?.cancel();

    final delay = scheduledTime.difference(DateTime.now());
    if (delay.isNegative) return;

    // Set up a new timer
    _scheduledTimers[id] = Timer(delay, () async {
      print('ALARM TRIGGERED: $title - $body');
      
      // Map ringtone names to our existing assets
      String assetFile = 'audio/join.wav';
      if (ringtone != null) {
        if (ringtone.toLowerCase().contains('beep')) {
          assetFile = 'audio/leave.wav';
        } else if (ringtone.toLowerCase().contains('chime')) {
          assetFile = 'audio/join.wav';
        }
      }

      try {
        await _audioPlayer.play(AssetSource(assetFile));
      } catch (e) {
        print('Failed to play audio: $e');
      }
    });
  }

  Future<void> cancelAll() async {
    for (final timer in _scheduledTimers.values) {
      timer.cancel();
    }
    _scheduledTimers.clear();
  }
}
