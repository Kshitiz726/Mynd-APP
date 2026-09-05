import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/account_scope.dart';
import '../core/services/photo_search.dart';
import '../core/services/quote_search.dart';
import '../core/services/place_service.dart';
import '../models/motivation.dart';
import 'task_provider.dart';
import '../services/notification_service.dart';
import 'memory_provider.dart';
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
  MemoryProvider? _memory;
  TaskProvider? _tasks;

  /// Late-bound so main.dart can build the providers in any order.
  ///
  /// Both are listened to rather than read at generation time. A line written
  /// this morning against a memory that has since changed, or against a mood
  /// somebody has since moved, is a line about a person who is no longer there.
  void bindMood(MoodProvider m) {
    if (identical(_mood, m)) return;
    _mood?.removeListener(_handChanged);
    _mood = m..addListener(_handChanged);
  }

  void bindMemory(MemoryProvider m) {
    if (identical(_memory, m)) return;
    _memory?.removeListener(_handChanged);
    _memory = m..addListener(_handChanged);
  }

  /// The day itself: what is blocked in, what got done, what is still waiting.
  ///
  /// Both a trigger and a source. A line written this morning against an empty
  /// day is the wrong line by the afternoon once four things are ticked off,
  /// and the app already knows that happened without being told.
  void bindTasks(TaskProvider t) {
    if (identical(_tasks, t)) return;
    _tasks?.removeListener(_dayChanged);
    _tasks = t..addListener(_dayChanged);
  }

  Timer? _rewrite;

  /// Re-rolled for every batch, so a live rewrite is not handed the same words
  /// back. Only ever seen by the model.
  String _nonce = '';

  /// Lines that came out of the mood banks rather than a category bank.
  ///
  /// Kept so the card does not label them. The category is assigned by slot,
  /// which is fine for a line written to a category and a small lie for one
  /// picked because somebody said they felt rough: the card was captioning
  /// "put it down, it is not going anywhere" as happiness.
  final Set<String> _moodBankTexts = {};

  /// The mood moved or the memory was rewritten, by hand.
  ///
  /// Debounced, and heavily: the memory notifies several times while it is
  /// being written, and the mood slider notifies for every segment somebody
  /// drags through on the way to the one they meant. [refresh] then compares
  /// signatures, so a notification that changed nothing costs a string compare
  /// rather than a model call.
  ///
  /// The card goes to its loading state on the line below, not 1200ms later
  /// when the write starts. Somebody who just moved their mood is looking at
  /// the card at that moment, and the debounce is a gap this code creates on
  /// purpose: without [_pending] the app answers a deliberate act with a
  /// second of nothing, which reads as having ignored it.
  void _handChanged() {
    if (!_settings.onboarded) return;
    // Did anything actually move? A provider notifies when it fails as well as
    // when it changes, and a memory refresh that comes back empty-handed
    // notifies on every retry. Raising the loading state on those, and
    // restarting the debounce below with each one, left the card shimmering
    // over a rewrite that was never coming: the timer was reset more often
    // than it could fire. The signature is built from memory this class
    // already holds, so asking is cheap enough to ask every time.
    final signature = _signature();
    if (signature == _lastSignature) return;
    if (!_pending) {
      _pending = true;
      notifyListeners();
    }
    _rewrite?.cancel();
    // force: the signature gate exists to stop a launch burning a request, and
    // it is exactly wrong here. Moving the mood back to one you picked earlier
    // in the day matched the stored signature and returned the cached lines, so
    // the app answered a deliberate change with the words it had already shown
    // you. Anything the person actually did gets a fresh answer.
    //
    // immediate: a mood somebody set by hand is not part of a burst. The gap
    // in [refresh] is there to fold four tasks ticked in a row into one write;
    // applying it to a deliberate change meant a second mood change inside
    // three minutes was answered with silence and no loading state at all.
    _rewrite = Timer(const Duration(milliseconds: 1200),
        () => refresh(force: true, immediate: true));
  }

  /// The day moved: something was scheduled, ticked off, or dropped.
  ///
  /// Nobody asked for new words here, so this keeps the gap and leaves the
  /// current line on screen until the write actually begins. Blanking the card
  /// to a skeleton every time a checkbox is ticked would be noise.
  void _dayChanged() {
    if (!_settings.onboarded) return;
    _rewrite?.cancel();
    _rewrite =
        Timer(const Duration(milliseconds: 1200), () => refresh(force: true));
  }

  /// They came back to the app. Worth a fresh look at the day.
  ///
  /// Forced. "Nothing in the signature moved" and "there is nothing new to
  /// say" are not the same claim, and the unforced version made them one: the
  /// signature only turns over on the hour, so opening the app was met with
  /// the same sentence and no sign the app had looked. The gap below still
  /// applies, so flicking away and back inside three minutes does not write
  /// twice - opening the app ten times in a minute is still not ten new
  /// situations.
  Future<void> onResumed() => refresh(force: true);

  /// The shortest gap between two live writes.
  ///
  /// Ticking four tasks off in a row is one burst of activity, not four
  /// separate moments worth writing about. A write inside the gap is not
  /// dropped, it is deferred: the timer below fires when the gap expires and
  /// writes against whatever the situation is by then, which is fresher than
  /// what it would have written at the time anyway.
  /// What the lines on screen were written against.
  ///
  /// Held in memory beside the persisted copy so [_handChanged] can tell a
  /// change from a notification, without a preferences read on every tick.
  String? _lastSignature;

  static const _minGap = Duration(minutes: 3);

  /// The floor under a hand-made change, which skips [_minGap].
  ///
  /// Not zero. The memory provider notifies whenever it retries, and a failing
  /// refresh retries, so "write immediately on every notification" is one
  /// unlucky network condition away from writing in a loop. Twenty seconds is
  /// far enough below the pace a person changes their mind that they will
  /// never meet it, and far enough above a retry that a storm cannot.
  static const _handGap = Duration(seconds: 20);
  DateTime? _lastWrite;
  Timer? _deferred;

  /// How long the loading state stays up once it is up.
  ///
  /// Without this the state was real but invisible. A rewrite that falls back
  /// to the local bank finishes in about the time it takes to lose a frame, so
  /// the skeleton appeared and vanished inside a single blink - present in the
  /// widget tree, never actually seen, and indistinguishable from a flicker on
  /// the occasions it was. Work that is over that fast still has to look like
  /// work rather than a glitch.
  static const _minVisible = Duration(milliseconds: 900);

  /// How long the whole write may spend looking for words, and then pictures,
  /// before it settles for what it has. Together they are the longest the card
  /// can sit in its loading state.
  static const _wordsBudget = Duration(seconds: 12);
  static const _picturesBudget = Duration(seconds: 8);
  DateTime? _busySince;

  /// A request that arrived while a write was already running.
  bool _queued = false;
  bool _queuedForce = false;
  bool _queuedImmediate = false;

  @override
  void dispose() {
    _rewrite?.cancel();
    _deferred?.cancel();
    _mood?.removeListener(_handChanged);
    _memory?.removeListener(_handChanged);
    _tasks?.removeListener(_dayChanged);
    super.dispose();
  }

  static const _kSettings = 'om_motivation_settings';
  static const _kLines = 'om_motivation_lines';
  static const _kWrittenOn = 'om_motivation_written_on';

  /// What the day's lines were written against. Stored beside them so a rewrite
  /// happens when the person changed, not merely when the date did.
  static const _kSignature = 'om_motivation_signature';

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

  /// A rewrite has been committed to but has not started yet.
  ///
  /// The window between somebody moving their mood and the debounce expiring.
  /// Separate from [_busy] because [_busy] also guards re-entry into [refresh],
  /// and a flag that says "a write is running" cannot also mean "a write is
  /// about to run" without letting one start twice.
  bool _pending = false;

  /// What the card asks. Either half of this means the words on screen are
  /// about to be replaced, which is the only thing the card needs to know.
  bool get working => _busy || _pending;

  /// Nothing is coming after all: the signature had not moved, or the write
  /// was deferred into the gap. Either way the current line stands, and
  /// leaving the skeleton up would be a promise the provider is not keeping.
  void _clearPending() {
    if (!_pending) return;
    _pending = false;
    notifyListeners();
  }

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
      if (lines != null && !_settings.onboarded) {
        // Lines with no settings beside them were not written for whoever is
        // signed in now. The only route to onboarded is the setup screen, and
        // it persists the settings, so this pairing can only be a write that
        // landed after an account switch. Somebody else's words about somebody
        // else's week: they are not shown, and they do not sit on disk. It
        // also restores the way in - the card sends a tap to setup only while
        // there is no line to open instead.
        await p.remove(_kLines);
        await p.remove(_kWrittenOn);
        await p.remove(_kSignature);
      } else if (lines != null) {
        _lines = [
          for (final j in jsonDecode(lines) as List)
            MotivationLine.fromJson(j as Map<String, dynamic>),
        ];
      }
      _lastSignature = p.getString(_kSignature);
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
  Future<void> refresh({bool force = false, bool immediate = false}) async {
    if (_busy) {
      // A write is already running, and this is a second request arriving on
      // top of it - which is the ordinary case at launch, where the card asks
      // for one and the mood finishes loading a beat later and asks again.
      //
      // Dropping it here was wrong twice over: the newer request is the one
      // that knows about the change, and _pending was already raised on its
      // behalf, so returning without either serving it or taking the flag back
      // down left the card on its skeleton with nothing left to clear it. Run
      // it when the current write finishes instead.
      _queued = true;
      _queuedForce = _queuedForce || force;
      _queuedImmediate = _queuedImmediate || immediate;
      return;
    }
    if (!_settings.onboarded) {
      _clearPending();
      return;
    }
    final now = DateTime.now();
    final today = _dayKey(now);
    final signature = _signature();

    // Has anything about them actually moved since these lines were written?
    // The signature covers the mood, the profile, the parked thoughts and the
    // day's schedule, so this is the real question rather than a proxy for it.
    var contextChanged = true;
    try {
      final p = await SharedPreferences.getInstance();
      contextChanged = !(p.getString(_kWrittenOn) == today &&
          p.getString(_kSignature) == signature &&
          _lines.isNotEmpty);
    } catch (_) {/* fall through and rewrite */}

    if (!contextChanged && !force) {
      _clearPending();
      return;
    }

    // Inside the gap: defer rather than drop. Writing again in ninety seconds
    // against the situation as it is THEN is both cheaper and more accurate
    // than writing twice about the same moment.
    final last = _lastWrite;
    final gap = immediate ? _handGap : _minGap;
    if (last != null && now.difference(last) < gap) {
      _deferred?.cancel();
      _deferred = Timer(gap - now.difference(last),
          () => refresh(force: force, immediate: immediate));
      // The skeleton does not sit there for the length of the gap. It goes up
      // again when the deferred write actually starts.
      _clearPending();
      return;
    }
    _deferred?.cancel();

    _lastWrite = now;
    _busy = true;
    _pending = false;
    _busySince = DateTime.now();
    // A write takes a model call and a round of photo searches. Somebody can
    // sign out and back in as somebody else inside that.
    final startedUnder = AccountScope.generation;
    _nonce = Random().nextInt(1 << 32).toRadixString(36);
    notifyListeners();
    try {
      final mood = _mood?.today?.mood ?? _mood?.reading?.mood;
      // The place belonged to the local-news frame, which is gone. Held at null
      // so a stale town cannot end up printed under a quotation it has nothing
      // to do with.
      _place = null;
      final themes = _themes(mood);
      // Bounded, because the card is holding a loading state open for this.
      //
      // Each source has its own eight second timeout, which is fine per
      // request and useless in aggregate: six themes, their fallbacks and then
      // a picture search per distinct query add up to well over a minute in
      // the worst case, and every second of it is a skeleton on Home over
      // lines that are already written and perfectly good. A quotation nobody
      // has yet is worth less than the one they can already read.
      final quotes = await QuoteSearch.instance
          .forThemes(themes, want: min(_settings.count, maxPerDay))
          .timeout(_wordsBudget, onTimeout: () => const <Quote>[]);
      if (AccountScope.generation != startedUnder) {
        debugPrint('[motivation] account changed mid-write, discarding');
        return;
      }
      _lines = quotes.isEmpty
          // Offline, or every source down at once. The bank is the app's own
          // writing rather than a quotation, so nothing gets attributed.
          ? _attachTimes(
              _bank(min(_settings.count, maxPerDay),
                  _settings.categories.toList(), mood, signature),
              const [])
          : _attachTimes([for (final q in quotes) q.text],
              [for (final q in quotes) q.author]);
      // Searched after the words exist, because the search terms come from
      // them. Failures - and now slowness - leave imageUrl null, and the card
      // falls back to a photograph seeded from the words themselves, so the
      // only cost of giving up here is that the picture is chosen rather than
      // searched for.
      await _attachPictures(mood).timeout(_picturesBudget, onTimeout: () {});
      await _persistLines(today, signature);
      _lastSignature = signature;
      await _schedule();
    } catch (e) {
      debugPrint('[motivation] refresh failed: $e');
    } finally {
      final shown = DateTime.now().difference(_busySince ?? DateTime.now());
      if (shown < _minVisible) {
        await Future<void>.delayed(_minVisible - shown);
      }
      _busy = false;
      notifyListeners();
    }

    if (_queued) {
      _queued = false;
      final f = _queuedForce;
      final i = _queuedImmediate;
      _queuedForce = false;
      _queuedImmediate = false;
      await refresh(force: f, immediate: i);
    }
  }

  /// What the lines were written against: the mood, the profile, the thoughts
  /// they parked, and the settings that shape the ask.
  ///
  /// This is the whole point of the rewrite trigger. It has to change when the
  /// person's situation changes and hold still otherwise, or the app either
  /// never updates or burns a model call on every rebuild.
  String _signature() {
    final mood = _mood?.today?.mood.name ?? _mood?.reading?.mood.name ?? '-';
    final cats = (_settings.categories.map((c) => c.name).toList()..sort())
        .join(',');
    // The hour is in here on purpose. Somebody who opens the app at eight in
    // the morning and again at six in the evening has not changed, but their
    // day has, and "you have got the whole day ahead of you" is the wrong
    // sentence the second time.
    final hour = DateTime.now().hour;
    return '$mood/${_settings.count}/$cats/$hour/'
        '${_stableHash(_memoryBlock())}';
  }

  /// Everything the app knows about them, as the model will be given it.
  String _memoryBlock() {
    final m = _memory;
    if (m == null) return '';
    final b = StringBuffer();
    final profile = m.memory.text.trim();
    if (profile.isNotEmpty) b.writeln(profile);
    final parked = m.parked.take(6).toList();
    if (parked.isNotEmpty) {
      b.writeln('\nThoughts they parked rather than chased, most recent first:');
      for (final t in parked) {
        b.writeln('- ${t.text}');
      }
    }
    return b.toString().trim();
  }

  /// FNV-1a. Spelled out because this is persisted, and String.hashCode is only
  /// promised to be consistent within a single run.
  static int _stableHash(String s) {
    var h = 0x811c9dc5;
    for (final unit in s.codeUnits) {
      h = ((h ^ unit) * 0x01000193) & 0xffffffff;
    }
    return h;
  }

  /// Pair each line with the clock slot it will arrive in.
  /// Spread [texts] across the day's slots, keeping each one's [authors] entry.
  ///
  /// An empty [authors] means the app wrote these itself, so nothing is
  /// attributed: a name under a sentence nobody said is an invented citation,
  /// and this card has form for claiming provenance it did not have.
  List<MotivationLine> _attachTimes(List<String> texts, List<String> authors) {
    final slots = _settings.slotMinutes;
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    final cats = _settings.categories.toList();
    return [
      for (var i = 0; i < texts.length && i < slots.length; i++)
        MotivationLine(
          text: texts[i],
          at: midnight.add(Duration(minutes: slots[i])),
          // No category on a line the mood chose. Labelling it with whichever
          // category the slot happened to land on is a claim about where the
          // words came from, and the wrong one.
          category: _moodBankTexts.contains(texts[i]) || cats.isEmpty
              ? null
              : cats[i % cats.length],
          author: i < authors.length ? authors[i] : null,
        ),
    ];
  }

  /// Which themes to ask the web for, from what the app knows about them.
  ///
  /// This is where the memory is actually used, and it is deliberately the
  /// only place: the quotations themselves are somebody else's words, chosen
  /// because they are about the right thing, not written about this person's
  /// task list. That was the complaint - lines like "the rent payment sits at
  /// the top" are a to-do list read back, not motivation - and it is why the
  /// schedule is no longer an input at all.
  ///
  /// Nothing personal leaves the device. The matching happens here and the
  /// request that goes out carries a single word like "Perseverance".
  @visibleForTesting
  List<String> themesFor(Mood? mood) => _themes(mood);

  List<String> _themes(Mood? mood) {
    final picked = <String>{};

    // What the mood asks for, first and weighted heaviest: on a rough day the
    // last thing wanted is Success and Opportunity.
    picked.addAll(switch (mood) {
      Mood.rough => const ['Pain', 'Wellness', 'Health', 'Time'],
      Mood.low => const ['Perseverance', 'Faith', 'Gratitude', 'Change'],
      Mood.okay => const ['Character', 'Wisdom', 'Life', 'Change'],
      Mood.good => const ['Courage', 'Creativity', 'Work', 'Opportunity'],
      Mood.great => const ['Success', 'Motivational', 'Opportunity', 'Future'],
      null => const ['Inspirational', 'Life', 'Wisdom'],
    });

    // Then what their own week is about. Read from the memory as themes, not
    // as subject matter: the word "deadline" in there should reach for
    // quotations about work, not produce a quotation about their deadline.
    final memory = _memoryBlock().toLowerCase();
    if (memory.isNotEmpty) {
      const cues = <String, String>{
        'tired': 'Wellness', 'sleep': 'Health', 'rest': 'Health',
        'anxious': 'Pain', 'worry': 'Pain', 'stress': 'Wellness',
        'stuck': 'Perseverance', 'behind': 'Perseverance',
        'procrastin': 'Work', 'avoid': 'Courage', 'afraid': 'Courage',
        'deadline': 'Work', 'project': 'Work', 'study': 'Knowledge',
        'exam': 'Knowledge', 'learn': 'Knowledge', 'money': 'Opportunity',
        'rent': 'Opportunity', 'family': 'Family', 'friend': 'Friendship',
        'lonely': 'Friendship', 'gym': 'Health', 'run': 'Health',
        'habit': 'Character', 'doubt': 'Self', 'confidence': 'Self',
        'fail': 'Failure', 'start': 'Change', 'change': 'Change',
      };
      for (final e in cues.entries) {
        if (memory.contains(e.key)) picked.add(e.value);
      }
    }

    // And the areas they chose at setup.
    for (final c in _settings.categories) {
      picked.add(switch (c) {
        MotivationCategory.selfEsteem => 'Self',
        MotivationCategory.happiness => 'Happiness',
        MotivationCategory.stress => 'Wellness',
        MotivationCategory.health => 'Health',
        MotivationCategory.goals => 'Success',
        MotivationCategory.lettingGo => 'Change',
        MotivationCategory.faith => 'Faith',
        MotivationCategory.relationships => 'Friendship',
      });
    }

    final out = picked.where(QuoteSearch.themes.contains).toList();
    // Shuffled on the nonce, so two rewrites in the same situation do not ask
    // for the same themes in the same order and come back with the same day.
    out.shuffle(Random(_stableHash('$_nonce/${picked.length}')));
    return out.take(6).toList();
  }

  /// Find a photograph on the web for each line.
  ///
  /// The terms come from the mood and from what the line is about, so a rough
  /// day gets quiet weather and a good one gets open light. Deliberately not
  /// one picture for the whole day: the card is a different sentence at nine in
  /// the morning and at nine at night, and reusing the image is most of what
  /// made it feel like nothing had changed.
  ///
  /// Searched a few at a time and reused across lines that share a theme, to
  /// keep this to a handful of requests rather than one per line.
  Future<void> _attachPictures(Mood? mood) async {
    final photos = PhotoSearch.instance;

    // Resolved once per distinct query rather than once per line, and in
    // parallel. A day is ten lines but only a handful of distinct searches, so
    // done line by line this was ten sequential round trips to fill in three
    // answers, and the card sat in its loading state for all of them.
    final queriesFor = {
      for (final l in _lines) l: _photoQueries(l, mood),
    };
    final distinct = {
      for (final qs in queriesFor.values) qs.join('|'): qs,
    };
    // The POOL per query, not one pick. Two lines sharing a theme still get
    // different photographs; collapsing this to one url per query would make
    // half the day identical, which is the thing the search was added to fix.
    final pools = <String, List<String>>{};
    await Future.wait(distinct.entries.map((e) async {
      try {
        pools[e.key] = await photos.poolFor(e.value);
      } catch (err) {
        debugPrint('[motivation] picture lookup failed: $err');
        pools[e.key] = const [];
      }
    }));

    final rand = Random();
    _lines = [
      for (final l in _lines)
        () {
          final pool = pools[queriesFor[l]!.join('|')] ?? const <String>[];
          if (pool.isEmpty) return l;
          return l.copyWith(imageUrl: pool[rand.nextInt(pool.length)]);
        }(),
    ];
  }

  /// What to search for, given the mood and the subject, most specific first.
  ///
  /// Landscape words rather than literal ones. Searching Commons for "self
  /// esteem" returns diagrams and stock illustration; searching for the weather
  /// a feeling looks like returns photographs, which is what the card wants
  /// behind two lines of text.
  static List<String> _photoQueries(MotivationLine l, Mood? mood) {
    final byMood = switch (mood) {
      Mood.rough => const ['soft mist morning', 'quiet rain window', 'still lake fog'],
      Mood.low => const ['overcast shore', 'calm forest path', 'grey sea horizon'],
      Mood.okay => const ['open field morning', 'quiet street light', 'calm river bank'],
      Mood.good => const ['sunlight through trees', 'clear coastline', 'open sky field'],
      Mood.great => const ['mountain sunrise', 'wide open horizon', 'bright summit view'],
      null => const ['landscape morning light', 'calm horizon', 'quiet nature'],
    };
    final byCategory = switch (l.category) {
      MotivationCategory.health => 'trail morning',
      MotivationCategory.relationships => 'two figures walking',
      MotivationCategory.goals => 'path uphill',
      MotivationCategory.stress => 'still water',
      MotivationCategory.faith => 'sky clouds light',
      MotivationCategory.lettingGo => 'open sea',
      MotivationCategory.happiness => 'sunlight meadow',
      MotivationCategory.selfEsteem => 'lone tree landscape',
      null => '',
    };
    // The slot decides which of the mood's words, so lines in the same day do
    // not all search the same phrase and land on the same photograph.
    final pick = byMood[l.at.hour % byMood.length];
    return [
      if (byCategory.isNotEmpty) '$pick $byCategory',
      pick,
      // Last resort, and broad on purpose: better a landscape that only matches
      // the mood than a card with a hole in it.
      'landscape photograph',
    ];
  }

  Future<void> _persistLines(String day, String signature) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kLines, jsonEncode([for (final l in _lines) l.toJson()]));
      await p.setString(_kWrittenOn, day);
      await p.setString(_kSignature, signature);
    } catch (e) {
      debugPrint('[motivation] line persist failed: $e');
    }
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
    'Nothing has to be decided today. It can all wait until you are steadier.',
    'You are allowed to do the bare minimum and call it a day.',
    'This is a day to be survived, not optimised.',
    'The list will still be there tomorrow. So will you.',
    'You do not have to explain why today is hard.',
    'Rest is not something you have to earn first.',
    'Being upright and fed is a real thing to have done.',
    'You are not behind. Today is just heavy.',
    'Put it down. It is not going anywhere.',
    'Small and slow still counts as moving.',
  ];

  /// Lines for a day somebody has said is going well. Not cheerleading: the
  /// point of a good day in this app is that it is the one where the thing you
  /// have been avoiding is actually within reach.
  static const _lift = [
    'Good day to start the thing you keep almost starting.',
    'You have got some room today. Spend a little of it on what you actually want.',
    'This is the version of you that gets things done. Give it something real.',
    'Momentum is cheap to keep and expensive to restart. Keep it.',
    'Pick the thing you have been circling and take one real bite out of it.',
    'Days like this are for the work that scares you slightly.',
    'Use the good hours on something that will still matter next month.',
    'You will not always feel like this. Get something down while you do.',
    'Spend it on the hard one. The easy ones will keep.',
    'This is a good day to make a future day easier.',
    'Do the thing while wanting to do it is free.',
    'Start the one you would normally put off until Monday.',
  ];

  /// The offline lines, for tests. What the bank returns is what most people
  /// actually see, since it is the path taken whenever the model is unreachable.
  @visibleForTesting
  List<String> bankLines(
          int n, List<MotivationCategory> cats, Mood? mood, String signature) =>
      _bank(n, cats, mood, signature);

  List<String> _bank(
      int n, List<MotivationCategory> cats, Mood? mood, String signature) {
    final rough = mood == Mood.rough || mood == Mood.low;
    final lifted = mood == Mood.good || mood == Mood.great;
    _moodBankTexts
      ..clear()
      ..addAll([if (rough) ..._gentle, if (lifted) ..._lift]);
    final pool = <String>[
      if (rough) ..._gentle,
      if (lifted) ..._lift,
      // On a rough day the category banks are held out entirely rather than
      // mixed in. "Start it badly, badly started is still started" is a good
      // line, and the wrong one to read ten minutes after saying you feel
      // rough. Mixing them was why moving the mood barely changed anything.
      if (!rough) for (final c in cats) ...(_fallback[c] ?? const []),
    ];
    if (pool.isEmpty) return List.filled(n, _gentle.first);
    // Seeded by the signature rather than the date, so moving the mood visibly
    // changes the lines even with no network. Seeded on the day alone, somebody
    // who said they felt rough got the same words back as an hour earlier and
    // reasonably concluded the slider was decorative.
    // Seeded by the signature AND the batch nonce. The signature alone pinned
    // the fallback to the mood, so the same mood twice gave the identical
    // lines; stability across rebuilds comes from the lines being persisted,
    // not from the seed, so there is nothing to lose by re-rolling here.
    final r = Random(_stableHash('$signature/$_nonce'));
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
