import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/groq_service.dart';

/// How the day feels, on a five-point scale. Rendered as gradient orbs rather
/// than emoji or numbers: naming a feeling is already work, picking one should
/// not be, and a system smiley is somebody else's art direction dropped into
/// the middle of the app.
enum Mood {
  rough(label: 'rough'),
  low(label: 'low'),
  okay(label: 'okay'),
  good(label: 'good'),
  great(label: 'great');

  const Mood({required this.label});

  final String label;

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

/// The app's own read on how someone is doing, inferred rather than asked.
///
/// This is a guess and is labelled as one everywhere it appears. It exists
/// because the days you least want to answer "how are you today?" are exactly
/// the days worth noticing, so the check-in goes unanswered precisely when it
/// would have mattered. [why] is the short reason, in the app's words, and it
/// is not optional: an unexplained verdict about your state of mind is worse
/// than no verdict, because you cannot argue with it.
class MoodReading {
  const MoodReading({required this.mood, required this.why, required this.at});

  final Mood mood;
  final String why;
  final DateTime at;

  Map<String, dynamic> toJson() =>
      {'mood': mood.name, 'why': why, 'at': at.toIso8601String()};

  factory MoodReading.fromJson(Map<String, dynamic> j) => MoodReading(
        mood: Mood.values.firstWhere((m) => m.name == j['mood'],
            orElse: () => Mood.okay),
        why: (j['why'] ?? '') as String,
        at: DateTime.parse(j['at'] as String),
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
  static const _kReading = 'om_mood_reading';

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
      final read = p.getString(_kReading);
      if (read != null) {
        _reading = MoodReading.fromJson(
            (jsonDecode(read) as Map).cast<String, dynamic>());
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

  // ─── The inferred read ────────────────────────────────────────────────────

  MoodReading? _reading;

  /// The app's guess at how they are doing. Null until it has actually been
  /// made: the gauge shows an empty dial rather than a default of "okay",
  /// because a needle resting at the middle is a claim, and a wrong one.
  MoodReading? get reading => _reading;

  bool _predicting = false;
  bool get predicting => _predicting;

  DateTime? _lastAttempt;

  /// Re-reading costs an API call and the answer moves slowly, so this is
  /// hourly at most, and only when the reading is stale by half a day. The
  /// autopilot asks on every memory change; this is what says no.
  static const _cooldown = Duration(hours: 1);
  static const _staleAfter = Duration(hours: 12);

  bool get wantsReading {
    if (!_loaded || _predicting) return false;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < _cooldown) {
      return false;
    }
    final r = _reading;
    return r == null || DateTime.now().difference(r.at) > _staleAfter;
  }

  /// Infer a mood from everything the app can see. [snapshot] is the same
  /// picture the memory is built from, assembled by the caller because only
  /// the widget tree has the other providers to hand.
  Future<void> predict(
    String snapshot, {
    String memory = '',
    String parked = '',
  }) async {
    if (_predicting) return;
    _predicting = true;
    _lastAttempt = DateTime.now();
    notifyListeners();

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '''
You read one user of an ADHD productivity app and estimate how they are doing.

You are given their profile, their schedule and how much of it actually
happened, their goals, their habits, what they have been saying to their coach,
and the thoughts they parked mid-focus. Weigh what they SAY and what they PARK
most heavily: an unfinished task list is normal for this user and is weak
evidence, while "I cannot do this anymore" in their own words is strong.

Answer with exactly one line, in this format, and nothing else:

MOOD|reason

MOOD is one of: rough, low, okay, good, great
reason is under 12 words, second person, plain, specific to them, lower case,
naming the real thing you read it from. No diagnosis, no advice, no praise.

Name a thing in their LIFE, never a thing in the app. Never say "your profile",
"your data", "the memory", "your check-ins", or "what you logged" - they know
where you got it, and it makes the reason sound like a database talking. Say
the deadline, the person, the task, the words they used.

Examples:
low|three days of parked thoughts all about the same deadline
good|you have been finishing what you start this week

If the evidence is thin, answer: okay|not much to go on yet''',
      },
      {
        'role': 'user',
        'content': [
          if (memory.isNotEmpty) 'Their profile:\n$memory\n',
          'What the app has seen:\n$snapshot',
          if (parked.isNotEmpty) '\nThoughts they parked:\n$parked',
        ].join('\n'),
      },
    ];

    try {
      final raw = await GroqService.instance.complete(messages);
      final parsed = _parse(raw);
      if (parsed != null) {
        _reading = parsed;
        final p = await SharedPreferences.getInstance();
        await p.setString(_kReading, jsonEncode(parsed.toJson()));
      }
    } catch (e) {
      // Silent by design. This is a background guess nobody asked for; a
      // failed one should leave the gauge exactly as it was.
      debugPrint('[mood] prediction failed: $e');
    } finally {
      _predicting = false;
      notifyListeners();
    }
  }

  /// Pull `mood|reason` out of the reply, tolerantly. A model that decides to
  /// add a sentence of preamble should not cost us the reading, but one that
  /// ignores the format entirely should not be guessed at either.
  static MoodReading? _parse(String raw) {
    for (final line in raw.split('\n')) {
      final i = line.indexOf('|');
      if (i <= 0) continue;
      final name = line.substring(0, i).trim().toLowerCase();
      final mood = Mood.values.where((m) => m.name == name).firstOrNull;
      if (mood == null) continue;
      var why = line.substring(i + 1).trim();
      if (why.length > 90) why = '${why.substring(0, 87)}...';
      return MoodReading(mood: mood, why: why, at: DateTime.now());
    }
    return null;
  }
}
