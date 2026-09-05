import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../utils/free_slots.dart';

/// The device's calendar, as much of it as this app needs.
///
/// Two directions, deliberately asymmetric:
///
///   Reading is the important half. Knowing when somebody is already busy is
///   what stops the planner laying work on top of a meeting, and it works with
///   read-only calendars, subscribed calendars and anything shared into the
///   phone.
///
///   Writing goes to ONE calendar the person picks, never to whichever one the
///   OS calls default. Writing into a shared work calendar because it happened
///   to sort first is the kind of mistake that emails other people.
class CalendarService {
  CalendarService._();
  static final CalendarService instance = CalendarService._();

  final _plugin = dc.DeviceCalendarPlugin();

  /// The connection and the id map, held in memory after the first read.
  ///
  /// Not an optimisation. Deleting one task used to cost three SharedPreferences
  /// round trips before the event was touched, and every one of them is a
  /// platform channel hop: the block vanished from the timeline and stayed on
  /// the calendar long enough to look broken. These are the only writer, so the
  /// cache cannot go stale behind our back.
  Map<String, String>? _map;
  bool? _enabledCache;
  String? _calIdCache;

  static const _kWriteCalendar = 'om_calendar_write_id';
  static const _kEnabled = 'om_calendar_enabled';

  /// Events this app created, by task id, so an edit updates the same event
  /// instead of leaving a duplicate behind every time a day is repacked.
  static const _kEventMap = 'om_calendar_event_ids';

  Future<bool> hasPermission() async {
    try {
      final r = await _plugin.hasPermissions();
      return r.isSuccess && r.data == true;
    } catch (e) {
      debugPrint('[calendar] permission check failed: $e');
      return false;
    }
  }

  /// Ask for access. Returns whether it was granted.
  Future<bool> requestPermission() async {
    try {
      if (await hasPermission()) return true;
      final r = await _plugin.requestPermissions();
      return r.isSuccess && r.data == true;
    } catch (e) {
      debugPrint('[calendar] permission request failed: $e');
      return false;
    }
  }

  /// Every calendar on the device.
  Future<List<dc.Calendar>> calendars() async {
    try {
      if (!await hasPermission()) return const [];
      final r = await _plugin.retrieveCalendars();
      return r.isSuccess ? (r.data?.toList() ?? const []) : const [];
    } catch (e) {
      debugPrint('[calendar] list failed: $e');
      return const [];
    }
  }

  /// Calendars this app is allowed to write into.
  ///
  /// A subscribed feed (a team rota, a holiday list) reports read-only, and
  /// offering it as a destination would produce a silent failure at the exact
  /// point somebody expects to see their task appear.
  Future<List<dc.Calendar>> writableCalendars() async =>
      [for (final c in await calendars()) if (c.isReadOnly != true) c];

  // The connection itself.

  Future<bool> get enabled async {
    final hit = _enabledCache;
    if (hit != null) return hit;
    try {
      final p = await SharedPreferences.getInstance();
      return _enabledCache = p.getBool(_kEnabled) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String?> get writeCalendarId async {
    final hit = _calIdCache;
    if (hit != null) return hit;
    try {
      final p = await SharedPreferences.getInstance();
      return _calIdCache = p.getString(_kWriteCalendar);
    } catch (_) {
      return null;
    }
  }

  Future<void> connect(String calendarId) async {
    _calIdCache = calendarId;
    _enabledCache = true;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kWriteCalendar, calendarId);
    await p.setBool(_kEnabled, true);
  }

  /// Stop syncing, without forgetting which events were ours.
  ///
  /// The mapping is kept on purpose: reconnecting later should update the
  /// events already out there rather than duplicating every one of them.
  Future<void> disconnect() async {
    _enabledCache = false;
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kEnabled, false);
  }

  // Reading.

  /// Everything already booked on [day], across every calendar on the device.
  ///
  /// All calendars, not just the writable one: somebody is just as busy during
  /// an event on a calendar the app cannot write to. All-day events are skipped
  /// because "on holiday" or "Dad's birthday" does not mean every hour of the
  /// day is unavailable, and treating it that way would leave the planner
  /// unable to place anything at all.
  ///
  /// Events this app wrote are excluded, and that is not an optimisation. They
  /// are the tasks being re-laid: counting them would mean the second press of
  /// Auto-Schedule saw yesterday's own output as a full day and placed nothing,
  /// with the day looking booked solid by work the app had just been asked to
  /// move. They are rewritten to their new times immediately afterwards.
  Future<List<Busy>> busyOn(DateTime day) async {
    try {
      if (!await hasPermission()) return const [];
      final mine = (await _eventMap()).values.toSet();
      final from = DateTime(day.year, day.month, day.day);
      final to = from.add(const Duration(days: 1));
      final out = <Busy>[];
      for (final cal in await calendars()) {
        final id = cal.id;
        if (id == null) continue;
        final r = await _plugin.retrieveEvents(
          id,
          dc.RetrieveEventsParams(startDate: from, endDate: to),
        );
        if (!r.isSuccess) continue;
        for (final e in r.data ?? const <dc.Event>[]) {
          if (e.allDay == true) continue;
          if (e.eventId != null && mine.contains(e.eventId)) continue;
          final s = e.start, en = e.end;
          if (s == null || en == null || !en.isAfter(s)) continue;
          out.add(Busy(_local(s), _local(en), title: e.title));
        }
      }
      return mergeBusy(out);
    } catch (e) {
      debugPrint('[calendar] busy lookup failed: $e');
      // Empty, not an exception. A calendar that will not answer must not stop
      // somebody planning their day; it only costs the conflict checking.
      return const [];
    }
  }

  /// Events on [day] that this app did not create, as candidates to mirror
  /// into the timeline.
  ///
  /// Filtered by the id map rather than by title, because a task called
  /// "Standup" pushed out and read back in would otherwise import itself as a
  /// second copy every time the day is opened.
  Future<List<CalendarEvent>> incomingOn(DateTime day) async {
    final mine = (await _eventMap()).values.toSet();
    final out = <CalendarEvent>[];
    try {
      if (!await hasPermission()) return out;
      final from = DateTime(day.year, day.month, day.day);
      final to = from.add(const Duration(days: 1));
      for (final cal in await calendars()) {
        final id = cal.id;
        if (id == null) continue;
        final r = await _plugin.retrieveEvents(
          id,
          dc.RetrieveEventsParams(startDate: from, endDate: to),
        );
        if (!r.isSuccess) continue;
        for (final e in r.data ?? const <dc.Event>[]) {
          final eid = e.eventId;
          final s = e.start, en = e.end;
          if (eid == null || s == null || en == null) continue;
          if (e.allDay == true) continue;
          if (mine.contains(eid)) continue;
          out.add(CalendarEvent(
            id: eid,
            title: (e.title ?? 'Event').trim(),
            start: _local(s),
            end: _local(en),
          ));
        }
      }
    } catch (e) {
      debugPrint('[calendar] incoming lookup failed: $e');
    }
    return out;
  }

  // Writing.

  /// Put a task on the calendar, or move the one already there.
  ///
  /// Returns the event id, or null when nothing was written. Failing quietly is
  /// deliberate here: the caller is a repack that may push twenty events, and
  /// one calendar refusing is not worth twenty error toasts.
  Future<String?> pushTask({
    required String taskId,
    required String title,
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      if (!await enabled) return null;
      final calId = await writeCalendarId;
      if (calId == null || !await hasPermission()) return null;

      final map = await _eventMap();
      final event = dc.Event(
        calId,
        // The existing event when there is one, so a moved task moves rather
        // than breeding a second copy at the new time.
        eventId: map[taskId],
        title: title,
        start: tz.TZDateTime.from(start, tz.local),
        end: tz.TZDateTime.from(end, tz.local),
        description: 'Planned in Mynd',
      );
      final r = await _plugin.createOrUpdateEvent(event);
      if (r == null || !r.isSuccess) {
        // Logged rather than swallowed. A refusal here looks identical to
        // "nothing to push" from the outside, and the whole feature failing
        // quietly is exactly how a sync people trust becomes a sync that has
        // silently done nothing for a week.
        debugPrint('[calendar] "$title" was refused: ${r?.errors.join('; ')}');
        return null;
      }
      final newId = r.data;
      if (newId != null) {
        map[taskId] = newId;
        await _saveEventMap(map);
      }
      return newId;
    } catch (e) {
      debugPrint('[calendar] push failed: $e');
      return null;
    }
  }

  /// Take a task's event back off the calendar.
  ///
  /// The event goes first and the bookkeeping second. Persisting the map before
  /// the delete would put a disk write between somebody swiping a block away and
  /// it leaving their calendar; the other order costs nothing if the app dies in
  /// between, because the worst case is a stale id that deletes an event which
  /// is already gone.
  Future<void> removeTask(String taskId) => removeTasks([taskId]);

  /// Several at once, persisting the map a single time.
  ///
  /// Deleting a task takes its chunk blocks with it, so "one deletion" is
  /// routinely three or four events, and doing the bookkeeping per event is how
  /// a single swipe turned into a visible pause.
  Future<void> removeTasks(Iterable<String> taskIds) async {
    try {
      final map = await _eventMap();
      final calId = await writeCalendarId;
      var changed = false;
      for (final taskId in taskIds) {
        final eventId = map.remove(taskId);
        if (eventId == null) continue;
        changed = true;
        if (calId != null) await _plugin.deleteEvent(calId, eventId);
      }
      if (changed) await _saveEventMap(map);
    } catch (e) {
      debugPrint('[calendar] delete failed: $e');
    }
  }

  /// A calendar time as a plain local DateTime.
  ///
  /// The plugin hands back TZDateTime, and reading its year/hour/minute fields
  /// directly gives the wall clock in ITS zone, not the phone's. That is
  /// invisible in UTC and exactly one hour wrong in British summer time, which
  /// is how a 4pm meeting was mirrored in as 3pm: the planner then protected
  /// the wrong hour and left the real meeting exposed. Going through the epoch
  /// converts properly whatever zone the event carries.
  static DateTime _local(DateTime t) =>
      DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch);

  /// The task ids that currently have an event on the calendar.
  Future<Iterable<String>> mappedTaskIds() async => (await _eventMap()).keys.toList();

  /// Task id to calendar event id.
  Future<Map<String, String>> _eventMap() async {
    final hit = _map;
    if (hit != null) return hit;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getStringList(_kEventMap) ?? const [];
      final out = <String, String>{};
      for (final entry in raw) {
        // Split on the FIRST space only: a calendar event id can contain
        // almost anything, so everything after the task id is the event id.
        final i = entry.indexOf(' ');
        if (i <= 0) continue;
        out[entry.substring(0, i)] = entry.substring(i + 1);
      }
      return _map = out;
    } catch (e) {
      debugPrint('[calendar] map read failed: $e');
      return _map = {};
    }
  }

  Future<void> _saveEventMap(Map<String, String> m) async {
    _map = m;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(
        _kEventMap,
        [for (final e in m.entries) '${e.key} ${e.value}'],
      );
    } catch (e) {
      debugPrint('[calendar] map persist failed: $e');
    }
  }
}

/// An event that came from the phone's calendar rather than from Mynd.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    required this.end,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime end;

  Duration get length => end.difference(start);
}
