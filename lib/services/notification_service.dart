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

  /// The tones the picker offers, lowercased to match `res/raw` file names.
  ///
  /// 'default' means the system notification sound and has no raw resource.
  static const tones = <String>['Default', 'Chime', 'Beep'];

  /// One channel per tone, because Android freezes a channel's sound when the
  /// channel is created and ignores every later change to it. Editing the sound
  /// of a single 'om_reminders' channel therefore did nothing at all - which is
  /// why every tone in the picker sounded identical no matter what was chosen.
  /// Switching tone now switches which channel the notification is posted to.
  ///
  /// The ids carry a v2 suffix: the original ids already exist on installed
  /// devices with the default sound baked in, and a channel cannot be mutated
  /// or meaningfully recreated under the same id once Android knows about it.
  static String _channelId({required bool alarm, required String tone}) =>
      '${alarm ? 'om_alarms' : 'om_reminders'}_v2_${tone.toLowerCase()}';

  static String _channelName({required bool alarm, required String tone}) =>
      alarm ? 'Alarms ($tone)' : 'Reminders ($tone)';

  static AndroidNotificationChannel _channel(
      {required bool alarm, required String tone}) {
    final raw = tone.toLowerCase();
    return AndroidNotificationChannel(
      _channelId(alarm: alarm, tone: tone),
      _channelName(alarm: alarm, tone: tone),
      description: alarm
          ? 'Alarms you set, at the time you set them.'
          : 'The things you asked to be reminded about.',
      importance: alarm ? Importance.max : Importance.high,
      // 'Default' deliberately passes no sound, so the phone's own
      // notification sound is used rather than one of ours.
      sound: raw == 'default'
          ? null
          : RawResourceAndroidNotificationSound(raw),
      playSound: true,
      enableVibration: true,
    );
  }

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
    // All six up front. Creating a channel is idempotent and cheap, and it has
    // to happen before anything is posted to it - a notification sent to an
    // unknown channel is dropped by Android without a word.
    for (final tone in tones) {
      await android?.createNotificationChannel(_channel(alarm: false, tone: tone));
      await android?.createNotificationChannel(_channel(alarm: true, tone: tone));
    }
    // The pre-v2 channels are stale now: their sound is baked in and nothing
    // posts to them any more. Left behind they would sit in system settings as
    // two dead entries the user can still toggle.
    await android?.deleteNotificationChannel('om_reminders');
    await android?.deleteNotificationChannel('om_alarms');

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

    // Ask iOS rather than assume. This returned a bare `true` on every
    // non-Android platform, so an iPhone that had denied notifications was told
    // by the reminders screen that everything was fine, and the one screen that
    // could have explained the silence instead confirmed it was working.
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final p = await ios.checkPermissions();
      return p?.isEnabled ?? false;
    }
    return true;
  }

  // ─── Scheduling ───────────────────────────────────────────────────────────

  /// The tone the user picked, as persisted by SettingsProvider.
  ///
  /// Read here rather than passed down from the UI: scheduling happens from
  /// providers and from the OS boot receiver, and neither has a BuildContext to
  /// read settings from.
  static const _kTone = 'om_selected_ringtone';

  Future<String> _selectedTone() async {
    final p = await SharedPreferences.getInstance();
    final saved = p.getString(_kTone) ?? 'Default';
    return tones.contains(saved) ? saved : 'Default';
  }

  Future<NotificationDetails> _details({required bool alarm}) async {
    final tone = await _selectedTone();
    final raw = tone.toLowerCase();
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId(alarm: alarm, tone: tone),
        _channelName(alarm: alarm, tone: tone),
        channelDescription: alarm
            ? 'Alarms you set, at the time you set them.'
            : 'The things you asked to be reminded about.',
        // Repeated on the notification as well as the channel. The channel is
        // what Android actually honours, but a mismatch here makes the two
        // disagree in system settings.
        sound: raw == 'default'
            ? null
            : RawResourceAndroidNotificationSound(raw),
        importance: alarm ? Importance.max : Importance.high,
        priority: alarm ? Priority.max : Priority.high,
        category: alarm
            ? AndroidNotificationCategory.alarm
            : AndroidNotificationCategory.reminder,
        fullScreenIntent: alarm,
        // Show the whole thing on the lock screen. The default hides content
        // behind "contents hidden", which is exactly the moment a reminder is
        // most useful: phone face down, screen off, glance at it and see what
        // it was without unlocking.
        visibility: NotificationVisibility.public,
        // Wake the display for it. Without this a reminder can land silently in
        // the shade while the screen stays dark, which is indistinguishable
        // from never arriving.
        ticker: alarm ? 'alarm' : 'reminder',
        enableLights: true,
        ledColor: const Color(0xFF6C5CE7),
        ledOnMs: 1000,
        ledOffMs: 500,
        // Brand colour behind the monochrome glyph, so a reminder is
        // recognisably ours in a crowded shade.
        color: const Color(0xFF6C5CE7),
      ),
      // iOS gets the same treatment rather than the defaults: a banner with
      // sound, and time-sensitive so it still breaks through a Focus mode the
      // way a reminder is expected to. Critical alerts are deliberately not
      // used - those need an Apple entitlement and are for safety alerts.
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        // The chosen tone here too. Android carries the sound on the channel,
        // which is why there is one channel per tone up there; iOS carries it
        // on the notification, and names a file inside the app bundle rather
        // than a Flutter asset. The two files live in ios/Runner/Sounds and
        // have to be members of the Runner target - see the iOS notes in the
        // setup brief. If one is missing iOS falls back to the default sound
        // rather than failing, so a mis-set bundle is quiet, not broken.
        sound: raw == 'default' ? null : '$raw.wav',
        // Time-sensitive for both: it breaks through Focus modes and shows on
        // the lock screen, which is the Android behaviour above. Critical would
        // also ignore the silent switch, but that needs an entitlement Apple
        // grants for safety alerts, so it is not something to reach for here.
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
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
      if (!daily) {
        // Logged rather than silent. Setting a one-off for a minute that has
        // just gone looks identical to setting one that works, and then nothing
        // ever arrives - which reads as broken notifications rather than as a
        // time already past.
        debugPrint('[notify] #$id at $when is already past, not scheduled');
        return;
      }
      when = when.add(const Duration(days: 1)); // same clock time, tomorrow
      debugPrint('[notify] #$id today has passed, first fire is $when');
    }

    // Resolved once, not per attempt: the ladder below can call put() three
    // times, and re-reading prefs each time is pointless work.
    final details = await _details(alarm: alarm);

    Future<void> put(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: mode,
          // The wall-clock time in the user's own zone, which is what a
          // reminder means. Interpreting it as wall time would move it when
          // they cross a timezone; absolute keeps "9am" at the 9am they set.
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: daily ? DateTimeComponents.time : null,
        );

    // Ask whether exact alarms are actually permitted rather than waiting to be
    // told by an exception - because we never are. Without the "alarms &
    // reminders" grant the plugin does not refuse `exactAllowWhileIdle`, it
    // silently downgrades it to an inexact alarm with a delivery window up to an
    // hour wide. Every reminder therefore reported itself as "scheduled exact"
    // in the log while the OS held it as inexact, and the alarmClock fallback
    // below could never be reached.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final canExact = await android?.canScheduleExactNotifications() ?? true;

    // setAlarmClock() first, for everything.
    //
    // It is the one delivery mode Android will not batch, defer past Doze, or
    // let an OEM battery manager sit on, because it is what the clock app uses,
    // and it needs no exact-alarm permission. Measured on a ColorOS phone:
    // `exactAllowWhileIdle` was accepted without complaint and the OS still
    // held every alarm with `windowLength 3600000`, a full hour of slack, which
    // is why reminders kept arriving late or seeming not to arrive at all. Only
    // alarmClock produced a zero window there.
    //
    // The cost is the system's next-alarm indicator. For an app whose whole
    // promise is that a reminder finds you, that is the right trade.
    try {
      await put(AndroidScheduleMode.alarmClock);
      lastScheduleWasApproximate = false;
      debugPrint('[notify] scheduled #$id via alarmClock for $when');
      return;
    } on PlatformException catch (e) {
      debugPrint('[notify] alarmClock refused, falling back: $e '
          '(canExact=$canExact)');
    }

    try {
      await put(AndroidScheduleMode.exactAllowWhileIdle);
      lastScheduleWasApproximate = false;
      debugPrint('[notify] scheduled #$id exact for $when');
      return;
    } on PlatformException catch (e) {
      debugPrint('[notify] exact schedule refused: $e');
    }

    // Exact was refused - the user never granted "alarms & reminders", or the
    // OEM is strict. Do NOT drop to inexact yet: Android gives those a window
    // up to an hour wide, and a reminder that lands 40 minutes late reads as one
    // that never came. setAlarmClock is refused far less often and needs no
    // permission, so it is the better second choice even for a plain reminder.
    try {
      await put(AndroidScheduleMode.alarmClock);
      lastScheduleWasApproximate = false;
      debugPrint('[notify] scheduled #$id via alarmClock for $when');
      return;
    } on PlatformException catch (e) {
      debugPrint('[notify] alarmClock refused too: $e');
    }

    // Last resort. Late beats never, but the user deserves to know their
    // reminders are approximate rather than concluding the app is broken.
    //
    // Guarded because a throw here escapes schedule() and aborts the caller's
    // whole loop: one reminder the OS dislikes would take every reminder after
    // it down with it, which is how a single failure became "notifications do
    // not work at all".
    try {
      await put(AndroidScheduleMode.inexactAllowWhileIdle);
      lastScheduleWasApproximate = true;
      debugPrint('[notify] scheduled #$id INEXACT for $when - delivery may be '
          'up to an hour late until exact alarms are allowed');
    } catch (e) {
      debugPrint('[notify] #$id could not be scheduled at all: $e');
    }
  }

  /// True when the last schedule could only be placed inexactly, so reminders
  /// may arrive up to an hour late. The reminders screen surfaces this: the
  /// alternative is a user who thinks notifications are simply broken.
  bool lastScheduleWasApproximate = false;

  /// Fire one right now. This is how the reminders screen can prove
  /// notifications work, which otherwise you only learn by waiting.
  Future<void> showNow({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();
    await _plugin.show(id, title, body, await _details(alarm: false));
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
