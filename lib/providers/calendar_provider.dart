import 'package:device_calendar/device_calendar.dart' as dc;
import 'package:flutter/foundation.dart';

import '../core/services/calendar_service.dart';
import '../core/utils/free_slots.dart';
import '../models/energy_level.dart';
import '../models/task.dart';

/// The app's side of the phone's calendar.
///
/// Holds the connection, caches what a day is already booked with, and moves
/// events in both directions. The arithmetic that decides where something fits
/// lives in free_slots.dart, with tests: a wrong answer there is a task laid on
/// top of a meeting, and that is the whole point of this feature.
class CalendarProvider extends ChangeNotifier {
  final _service = CalendarService.instance;

  bool _connected = false;
  bool get connected => _connected;

  String? _calendarId;
  String? get calendarId => _calendarId;

  String? _calendarName;

  /// The name of the calendar being written to, for saying so in the UI. A
  /// connection nobody can see the destination of is one people distrust.
  String? get calendarName => _calendarName;

  List<dc.Calendar> _writable = const [];
  List<dc.Calendar> get writable => _writable;

  bool _busyState = false;
  bool get busy => _busyState;

  /// Busy blocks per day, so opening the same day twice does not re-read every
  /// calendar on the phone. Cleared whenever anything is written.
  final Map<String, List<Busy>> _cache = {};

  Future<void> load() async {
    _connected = await _service.enabled;
    _calendarId = await _service.writeCalendarId;
    if (_connected) {
      _writable = await _service.writableCalendars();
      _calendarName = _nameFor(_calendarId);
    }
    notifyListeners();
  }

  String? _nameFor(String? id) {
    if (id == null) return null;
    for (final c in _writable) {
      if (c.id == id) return c.name;
    }
    return null;
  }

  /// Ask for access and list the calendars that can be written to.
  ///
  /// Returns false when permission was refused, so the caller can say so
  /// rather than showing an empty list that looks like a phone with no
  /// calendars on it.
  Future<bool> requestAccess() async {
    _busyState = true;
    notifyListeners();
    try {
      final ok = await _service.requestPermission();
      if (ok) _writable = await _service.writableCalendars();
      return ok;
    } finally {
      _busyState = false;
      notifyListeners();
    }
  }

  Future<void> connect(String calendarId) async {
    await _service.connect(calendarId);
    _connected = true;
    _calendarId = calendarId;
    _calendarName = _nameFor(calendarId);
    _cache.clear();
    notifyListeners();
  }

  Future<void> disconnect() async {
    await _service.disconnect();
    _connected = false;
    _cache.clear();
    notifyListeners();
  }

  /// What is already booked on [day].
  ///
  /// Read even when the connection is off, as long as permission was granted:
  /// somebody who has allowed the app to see their calendar wants their
  /// meetings respected whether or not they also want tasks written back.
  Future<List<Busy>> busyOn(DateTime day) async {
    final key = _key(day);
    final hit = _cache[key];
    if (hit != null) return hit;
    final blocks = await _service.busyOn(day);
    _cache[key] = blocks;
    return blocks;
  }

  void invalidate() {
    _cache.clear();
  }

  /// Push every task placed on [day] out to the calendar.
  ///
  /// Anchors and chunks are skipped. A wake-up routine and a wind-down are the
  /// app's own furniture rather than appointments, and filling somebody's
  /// calendar with them is how a sync feature gets turned off on day one.
  Future<int> pushDay(List<Task> tasks, DateTime day) async {
    if (!_connected) return 0;
    var pushed = 0;
    for (final t in tasks) {
      if (t.isAnchor || t.isChunk || t.done) continue;
      if (t.id.startsWith(importedPrefix)) continue; // came FROM the calendar
      final start = t.startTime;
      if (start == null || !_sameDay(start, day)) continue;
      final end = t.endTime;
      if (end == null) continue;
      final id = await _service.pushTask(
        taskId: t.id,
        title: t.title,
        start: start,
        end: end,
      );
      if (id != null) pushed++;
    }
    if (pushed > 0) _cache.clear();
    return pushed;
  }

  /// Take a task's event back off the calendar, for when it is deleted here.
  Future<void> remove(String taskId) => _service.removeTask(taskId);

  /// Ids of imported events carry this, so nothing pushes them back out and
  /// creates a loop of the app and the calendar copying one event forever.
  static const importedPrefix = Task.calendarPrefix;

  /// The phone's own events for [day], as timeline blocks.
  ///
  /// Marked as anchors because they are not the app's to move: a repack that
  /// slides somebody's dentist appointment an hour later has told them a
  /// comfortable lie about when it is.
  Future<List<Task>> importDay(DateTime day) async {
    final events = await _service.incomingOn(day);
    // Counted out loud. Zero imported events and a calendar the app cannot
    // read look identical from the outside, and the difference is the whole
    // feature.
    debugPrint('[calendar] ${events.length} event(s) to mirror in for '
        '${day.year}-${day.month}-${day.day}');
    return [
      for (final e in events)
        Task(
          id: '$importedPrefix${e.id}',
          title: e.title,
          time: 'Calendar',
          energy: EnergyLevel.low,
          isAnchor: true,
        )
          ..scheduled = true
          ..startTime = e.start
          ..duration = e.length,
    ];
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _key(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
