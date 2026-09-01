import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/groq_service.dart';
import '../core/services/local_news.dart';
import '../core/services/place_service.dart';
import '../models/motivation.dart';
import '../services/notification_service.dart';
import 'mood_provider.dart';

/// The day's motivation: what it says, when it arrives, and why.
///
/// Lines are written a day at a time and scheduled ahead, not generated when a
/// notification fires. iOS will not wake an app to compose a notification it is
/// about to show, so anything that has to be decided at delivery time simply
/// never arrives. Writing the whole day up front is the only shape that works,
/// and it also means a day with no signal still has ten lines waiting.
class MotivationProvider extends ChangeNotifier {
  MotivationProvider({MoodProvider? mood}) : _mood = mood;

  MoodProvider? _mood;

  /// Late-bound so main.dart can build the providers in any order.
  void bindMood(MoodProvider m) => _mood = m;

  static const _kSettings = 'om_motivation_settings';
  static const _kLines = 'om_motivation_lines';
  static const _kWrittenOn = 'om_motivation_written_on';

  /// Notification ids live in their own block so cancelling the day's lines
  /// cannot take a reminder or an alarm with them.
  static const _idBase = 770000;

  /// The OS keeps a limited number of pending notifications (64 on iOS, shared
  /// with everything else the app schedules). Twelve a day leaves room for
  /// reminders and alarms, and is already more motivation than anyone wants.
  static const maxPerDay = 12;

  MotivationSettings _settings = const MotivationSettings();
  MotivationSettings get settings => _settings;

  List<MotivationLine> _lines = const [];
  List<MotivationLine> get lines => _lines;

  /// The most recent line, for showing in the app rather than only in a banner.
  MotivationLine? get latest {
    final now = DateTime.now();
    MotivationLine? best;
    for (final l in _lines) {
      if (l.at.isAfter(now)) continue;
      if (best == null || l.at.isAfter(best.at)) best = l;
    }
    return best ?? (_lines.isEmpty ? null : _lines.first);
  }

  bool _busy = false;
  bool get busy => _busy;

  String? _place;
  String? get place => _place;

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kSettings);
      if (raw != null) {
        _settings = MotivationSettings.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
      }
      final lines = p.getString(_kLines);
      if (lines != null) {
        _lines = [
          for (final j in jsonDecode(lines) as List)
            MotivationLine.fromJson(j as Map<String, dynamic>),
        ];
      }
      _place = await PlaceService.instance.lastKnown();
      notifyListeners();
    } catch (e) {
      debugPrint('[motivation] load failed: $e');
    }
  }

  Future<void> save(MotivationSettings next) async {
    _settings = next;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kSettings, jsonEncode(next.toJson()));
    } catch (e) {
      debugPrint('[motivation] persist failed: $e');
    }
  }

  /// Write today's lines and put them in the schedule.
  ///
  /// Safe to call on every launch: it returns immediately when today is already
  /// written, so it costs one string comparison rather than an LLM call.
  Future<void> refresh({bool force = false}) async {
    if (_busy || !_settings.onboarded) return;
    final today = _dayKey(DateTime.now());
    if (!force) {
      try {
        final p = await SharedPreferences.getInstance();
        if (p.getString(_kWrittenOn) == today && _lines.isNotEmpty) return;
      } catch (_) {/* fall through and rewrite */}
    }

    _busy = true;
    notifyListeners();
    try {
      _place = await PlaceService.instance.resolve();
      final headlines =
          _place == null ? const <String>[] : await LocalNews.headlines(_place!);
      final texts = await _write(headlines);
      _lines = _attachTimes(texts, headlines);
      await _persistLines(today);
      await _schedule();
    } catch (e) {
      debugPrint('[motivation] refresh failed: $e');
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Pair each line with the clock slot it will arrive in.
  List<MotivationLine> _attachTimes(List<String> texts, List<String> headlines) {
    final slots = _settings.slotMinutes;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final cats = _settings.categories.toList();
    return [
      for (var i = 0; i < texts.length && i < slots.length; i++)
        MotivationLine(
          text: texts[i],
          at: midnight.add(Duration(minutes: slots[i])),
          category: cats.isEmpty ? null : cats[i % cats.length],
          place: _place,
          // Only claim a source where there was one to draw on.
          source: headlines.isEmpty ? null : headlines[i % headlines.length],
        ),
    ];
  }

  Future<void> _persistLines(String day) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kLines, jsonEncode([for (final l in _lines) l.toJson()]));
      await p.setString(_kWrittenOn, day);
    } catch (e) {
      debugPrint('[motivation] line persist failed: $e');
    }
  }

  /// Ask the model for the day's lines, or fall back to the written bank.
  Future<List<String>> _write(List<String> headlines) async {
    final n = min(_settings.count, maxPerDay);
    final cats = _settings.categories.isEmpty
        ? MotivationCategory.values.toList()
        : _settings.categories.toList();
    final mood = _mood?.today?.mood ?? _mood?.reading?.mood;

    try {
      final out = await GroqService.instance.complete([
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': _userPrompt(n, cats, mood, headlines)},
      ]);
      final parsed = _parseLines(out, n);
      if (parsed.length >= n) return parsed;
      // A short answer is topped up rather than thrown away: nine good lines
      // and one from the bank beats ten from the bank.
      return [...parsed, ..._bank(n - parsed.length, cats, mood)];
    } catch (e) {
      // Every failure lands here on purpose. Motivation that only works with a
      // signal and a working API key is motivation that is missing on exactly
      // the flat, disconnected days it was built for.
      debugPrint('[motivation] generation failed, using the bank: $e');
      return _bank(n, cats, mood);
    }
  }

  static const _systemPrompt =
      'You write short daily motivation lines for a focus app used by people '
      'with ADHD. Rules: one sentence each, under 110 characters, second '
      'person, plain words, no emoji, no hashtags, no quotation marks, never '
      'start with "Remember". Do not be cheerful at someone who is struggling. '
      'Return only the lines, one per line, numbered 1. 2. 3. and nothing else.';

  String _userPrompt(int n, List<MotivationCategory> cats, Mood? mood,
      List<String> headlines) {
    final b = StringBuffer()
      ..writeln('Write $n lines for today.')
      ..writeln('Areas they want to work on: ${cats.map((c) => c.label).join(', ')}.');
    if (mood != null) {
      b.writeln('They said today feels "${mood.label}". Match that: a rough or '
          'low day wants steadiness, not enthusiasm.');
    }
    if (headlines.isNotEmpty && _place != null) {
      b
        ..writeln('They are in $_place. Today the local news there says:')
        ..writeln(headlines.map((h) => '- $h').join('\n'))
        ..writeln('You may ground at most two lines in something local and '
            'ordinary from that list. Skip anything grim, political or '
            'violent, and never mention a crime, a death or a disaster. If '
            'nothing there is suitable, ignore it entirely.');
    }
    return b.toString();
  }

  /// Pull numbered lines out of the model's answer.
  @visibleForTesting
  static List<String> parseLines(String raw, int want) => _parseLines(raw, want);

  static List<String> _parseLines(String raw, int want) {
    final out = <String>[];
    for (final line in const LineSplitter().convert(raw)) {
      var t = line.trim();
      if (t.isEmpty) continue;
      // Numbering, bullets and stray quotes, all of which the model adds back
      // however firmly the prompt asks it not to.
      t = t.replaceFirst(RegExp(r'^\s*(\d+[.)]|[-*•])\s*'), '').trim();
      t = t.replaceAll(RegExp(r'^["“]|["”]$'), '').trim();
      if (t.length < 8) continue;
      out.add(t);
      if (out.length >= want) break;
    }
    return out;
  }

  /// Written lines, used whenever the model cannot be reached.
  ///
  /// Deliberately quiet in tone. A line that turns up unbidden ten times a day
  /// has to be something somebody can read on their worst afternoon without
  /// wincing, which rules out most of what gets called motivational.
  static const _fallback = <MotivationCategory, List<String>>{
    MotivationCategory.lettingGo: [
      'You are allowed to put this one down and not pick it back up.',
      'The thing you are still turning over has already had its share of today.',
      'Not every open loop is yours to close.',
    ],
    MotivationCategory.faith: [
      'You do not have to see the whole staircase to take one step.',
      'Some things are carried rather than solved.',
      'Quiet is not the same as empty.',
    ],
    MotivationCategory.happiness: [
      'Something small today is going to be genuinely good. Let it count.',
      'You are allowed to enjoy a thing without earning it first.',
      'Notice one thing that went right before you list what did not.',
    ],
    MotivationCategory.stress: [
      'Slow the next breath down. Nothing here needs you at full speed.',
      'You can only do the next thing, and that is enough.',
      'The worry has been rehearsed enough times now.',
    ],
    MotivationCategory.health: [
      'A glass of water and a stretch is not nothing. Go and get both.',
      'Your body has been carrying you all day. Give it ten minutes.',
      'Rest is part of the work, not a break from it.',
    ],
    MotivationCategory.goals: [
      'Fifteen honest minutes beats a perfect hour you never start.',
      'Start it badly. Badly started is still started.',
      'The version of this you finish beats the version you plan.',
    ],
    MotivationCategory.selfEsteem: [
      'You are not behind. You are on your own timeline.',
      'The voice being hardest on you today is not the accurate one.',
      'You have done harder things than this with less in the tank.',
    ],
    MotivationCategory.relationships: [
      'Send the message. It is shorter to write than to keep meaning to.',
      'Someone would be glad to hear from you today.',
      'Being known beats being impressive.',
    ],
  };

  /// Lines that suit a day somebody has already said is hard, used instead of
  /// the category banks when the mood is low. Being told to seize the day when
  /// you have just said you feel rough is worse than being told nothing.
  static const _gentle = [
    'Today only has to be got through. That counts as doing it.',
    'Lower the bar. Meeting it is what matters now.',
    'You do not owe anyone a good day.',
    'Whatever you manage today is enough for today.',
  ];

  List<String> _bank(int n, List<MotivationCategory> cats, Mood? mood) {
    final rough = mood == Mood.rough || mood == Mood.low;
    final pool = <String>[
      if (rough) ..._gentle,
      for (final c in cats) ...(_fallback[c] ?? const []),
    ];
    if (pool.isEmpty) return List.filled(n, _gentle.first);
    // Seeded by the day, so the lines are stable if the app rewrites them and
    // different tomorrow without needing anything stored.
    final r = Random(DateTime.now().day * 31 + DateTime.now().month);
    final shuffled = [...pool]..shuffle(r);
    return [for (var i = 0; i < n; i++) shuffled[i % shuffled.length]];
  }

  /// Put the day's lines into the OS schedule.
  Future<void> _schedule() async {
    final notify = NotificationService.instance;
    // Clear the whole block first: yesterday's count may have been higher, and
    // a leftover from a longer day would fire with a line nobody wrote today.
    for (var i = 0; i < maxPerDay; i++) {
      await notify.cancel(_idBase + i);
    }
    if (!await notify.enabled) return;
    for (var i = 0; i < _lines.length && i < maxPerDay; i++) {
      final l = _lines[i];
      await notify.schedule(
        id: _idBase + i,
        title: 'Mynd',
        body: l.text,
        at: l.at,
        // Daily, so a day the app is never opened still has its lines. They are
        // overwritten the next time it runs, which is what keeps them fresh.
        daily: true,
      );
    }
  }

  /// Stop the lines without forgetting the settings, for turning the feature
  /// off from settings later.
  Future<void> cancelAll() async {
    for (var i = 0; i < maxPerDay; i++) {
      await NotificationService.instance.cancel(_idBase + i);
    }
  }

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
