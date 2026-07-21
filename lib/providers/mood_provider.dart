import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// How the day feels, on a five-point scale. Faces, not numbers - naming a
/// feeling is already work, and picking one should not be.
enum Mood {
  rough(label: 'rough', emoji: '😞'),
  low(label: 'low', emoji: '😕'),
  okay(label: 'okay', emoji: '😐'),
  good(label: 'good', emoji: '🙂'),
  great(label: 'great', emoji: '😄');

  const Mood({required this.label, required this.emoji});

  final String label;
  final String emoji;

  /// 0..1, for tinting and for the trend bar heights.
  double get value => (index + 1) / Mood.values.length;
}

/// One day's check-in.
class MoodEntry {
  const MoodEntry({required this.day, required this.mood, this.note});

  final DateTime day;
  final Mood mood;
  final String? note;

  Map<String, dynamic> toJson() => {
        'day': day.toIso8601String(),
        'mood': mood.name,
        if (note != null) 'note': note,
      };

  factory MoodEntry.fromJson(Map<String, dynamic> j) => MoodEntry(
        day: DateTime.parse(j['day'] as String),
        mood: Mood.values.firstWhere(
          (m) => m.name == j['mood'],
          orElse: () => Mood.okay,
        ),
        note: j['note'] as String?,
      );
}

/// Owns the daily mood check-in and the fortnight of history behind it.
///
/// The check-in is asked **once per day, on the first open** - asking again is
/// nagging, and a mood log that nags gets abandoned. [needsCheckIn] is what the
/// home screen watches.
class MoodProvider extends ChangeNotifier {
  MoodProvider() {
    load();
  }

  static const _kEntries = 'om_mood_entries';

  /// How much history we keep. Two weeks is enough to see a shape without
  /// turning Home into a chart.
  static const historyDays = 14;

  List<MoodEntry> _entries = [];
  List<MoodEntry> get entries => List.unmodifiable(_entries);

  bool _loaded = false;
  bool get loaded => _loaded;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Today's entry, if they have already checked in.
  MoodEntry? get today {
    final now = DateTime.now();
    for (final e in _entries) {
      if (_sameDay(e.day, now)) return e;
    }
    return null;
  }

  /// True once we know there is no entry for today - never true before the
  /// stored entries have loaded, or the sheet flashes up on every cold start.
  bool get needsCheckIn => _loaded && today == null;

  /// Oldest-first, one slot per day for the last [historyDays], with nulls for
  /// days that were missed. The gaps are the point: a skipped day is data.
  List<MoodEntry?> get recent {
    final now = DateTime.now();
    final out = <MoodEntry?>[];
    for (var i = historyDays - 1; i >= 0; i--) {
      final day = now.subtract(Duration(days: i));
      out.add(_entries.where((e) => _sameDay(e.day, day)).firstOrNull);
    }
    return out;
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kEntries);
      if (raw != null) {
        _entries = (jsonDecode(raw) as List)
            .map((e) => MoodEntry.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
    } catch (e) {
      debugPrint('[mood] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// Log (or change) today's mood. Re-checking in replaces the entry rather
  /// than adding a second one: a day has one mood in this model, and letting
  /// them correct it costs nothing.
  Future<void> checkIn(Mood mood, {String? note}) async {
    final now = DateTime.now();
    _entries.removeWhere((e) => _sameDay(e.day, now));
    _entries.add(MoodEntry(day: DateTime(now.year, now.month, now.day), mood: mood, note: note));
    // Keep a little more than we show, so the strip stays full after a gap.
    final cutoff = now.subtract(const Duration(days: historyDays * 2));
    _entries.removeWhere((e) => e.day.isBefore(cutoff));
    _entries.sort((a, b) => a.day.compareTo(b.day));
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kEntries, jsonEncode(_entries.map((e) => e.toJson()).toList()));
  }
}
