import 'dart:async';

import 'package:flutter/material.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Real notifications, from the operating system.
///
/// This used to be a [Timer] that played an asset when it fired, which meant a
/// reminder only arrived if the app was already open and in front of you. That
/// is the one moment you do not need reminding. Everything here goes through
/// the OS scheduler instead, so a reminder set for 9am arrives at 9am whether
/// the app is backgrounded, swiped away, or the phone has been asleep since.
class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  static NotificationService get instance => _instance;

  final _plugin = FlutterLocalNotificationsPlugin();

  /// Reminders and alarms get separate channels so they can be silenced
  /// separately in system settings. Somebody who wants their 6:30 alarm loud
  /// and their nudges quiet should not have to choose between them.
  static const _reminderChannel = AndroidNotificationChannel(
    'om_reminders',
    'Reminders',
    description: 'The things you asked to be reminded about.',
    importance: Importance.high,
  );

  static const _alarmChannel = AndroidNotificationChannel(
    'om_alarms',
    'Alarms',
    description: 'Alarms you set, at the time you set them.',
    importance: Importance.max,
  );

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;

    tzdata.initializeTimeZones();
    _useLocalZone();

    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          // Asked for explicitly at first launch instead, with a sentence of
          // explanation, so a system sheet is not the first thing a new user
          // sees.
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_reminderChannel);
    await android?.createNotificationChannel(_alarmChannel);

    _ready = true;
  }

  /// Point `tz.local` at a zone that agrees with this device about what time it
  /// is, by matching the current UTC offset.
  ///
  /// The obvious way is a plugin that reads the IANA zone name off the
  /// platform, and that is what this did until `flutter_timezone` turned out to
  /// compile its Kotlin at a JVM target Gradle now refuses to mix with. The
  /// offset is enough for what we do with it: every reminder is scheduled from
  /// a local wall-clock time, so a zone with the right offset produces the
  /// right instant. The cost is that a daily reminder can land an hour out for
  /// the day after a DST change, until the next resync corrects it, and this
  /// country does not observe DST anyway. Left as a comment because the
  /// tradeoff is not visible in the code.
  void _useLocalZone() {
    final offset = DateTime.now().timeZoneOffset;
    if (tz.local.currentTimeZone.offset == offset.inMilliseconds) return;
    final now = DateTime.now().toUtc();
    for (final location in tz.timeZoneDatabase.locations.values) {
      if (location.timeZone(now.millisecondsSinceEpoch).offset ==
          offset.inMilliseconds) {
        tz.setLocalLocation(location);
        return;
      }
    }
    debugPrint('[notify] no zone matched offset $offset, staying on UTC');
  }

  // ─── Permission ───────────────────────────────────────────────────────────

  static const _kAsked = 'om_notif_permission_asked';

  /// True once we have put the system prompt in front of them, whatever they
  /// answered. Android only allows the ask once, so a "no" is final until they
  /// go into system settings, and re-prompting would achieve nothing but
  /// irritation.
  Future<bool> hasBeenAsked() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_kAsked) ?? false;
  }

  /// Ask for everything a reminder needs: permission to post notifications
  /// (Android 13+, iOS always) and permission to schedule exact alarms
  /// (Android 12+). Without the second, Android is free to batch a 9:00
  /// reminder into a maintenance window and deliver it at 9:20, which for
  /// "take your meds" is a different thing entirely.
  Future<bool> requestPermissions() async {
    await init();
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kAsked, true);

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      final granted = await android.requestNotificationsPermission() ?? false;
      await android.requestExactAlarmsPermission();
      return granted;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
              alert: true, badge: true, sound: true) ??
          false;
    }
    return false;
  }

  Future<bool> get enabled async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  // ─── Scheduling ───────────────────────────────────────────────────────────

  NotificationDetails _details({required bool alarm}) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        alarm ? _alarmChannel.id : _reminderChannel.id,
        alarm ? _alarmChannel.name : _reminderChannel.name,
        channelDescription: alarm
            ? _alarmChannel.description
            : _reminderChannel.description,
        importance: alarm ? Importance.max : Importance.high,
        priority: alarm ? Priority.max : Priority.high,
        category: alarm
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,
        fullScreenIntent: alarm,
        // Brand colour behind the monochrome glyph, so a reminder is
        // recognisably ours in a crowded shade.
        color: const Color(0xFF6C5CE7),
      ),
      iOS: const DarwinNotificationDetails(),
    );
  }

  /// Put one notification on the OS schedule.
  ///
  /// [daily] repeats it at the same clock time every day; otherwise it fires
  /// once. A time already past is dropped rather than fired immediately: an
  /// alert for something that was due an hour ago is noise, not a reminder.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
    bool daily = false,
    bool alarm = false,
  }) async {
    await init();

    var when = tz.TZDateTime.from(at, tz.local);
    final now = tz.TZDateTime.now(tz.local);
    if (!when.isAfter(now)) {
      if (!daily) return;
      when = when.add(const Duration(days: 1)); // same clock time, tomorrow
    }

    Future<void> put(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          _details(alarm: alarm),
          androidScheduleMode: mode,
          // The wall-clock time in the user's own zone, which is what a
          // reminder means. Interpreting it as wall time would move it when
          // they cross a timezone; absolute keeps "9am" at the 9am they set.
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: daily ? DateTimeComponents.time : null,
        );

    try {
      await put(AndroidScheduleMode.exactAllowWhileIdle);
    } on PlatformException catch (e) {
      // Exact alarms can be refused: the user declined the permission, or the
      // OEM is strict about them. A reminder a few minutes late beats no
      // reminder, so fall back rather than losing it.
      debugPrint('[notify] exact schedule refused, falling back: $e');
      await put(AndroidScheduleMode.inexactAllowWhileIdle);
    }
  }

  /// Fire one right now. This is how the reminders screen can prove
  /// notifications work, which otherwise you only learn by waiting.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(id, title, body, _details(alarm: false));
  }

  Future<void> cancel(int id) async {
    await init();
    await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    await init();
    await _plugin.cancelAll();
  }

  /// What the OS actually has queued for us, so the UI can tell the truth about
  /// whether a nudge is really going to arrive.
  Future<List<PendingNotificationRequest>> pending() async {
    await init();
    return _plugin.pendingNotificationRequests();
  }

  // ─── Legacy shim ──────────────────────────────────────────────────────────

  /// The old signature, kept so existing callers keep working. Alarms go on the
  /// alarm channel and may take over the screen.
  Future<void> scheduleAlarm({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? ringtone,
  }) =>
      schedule(
        id: id,
        title: title,
        body: body,
        at: scheduledTime,
        alarm: true,
      );

  Future<void> cancelAlarm(int id) => cancel(id);
}
