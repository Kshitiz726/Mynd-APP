import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/groq_service.dart';
import '../models/user_memory.dart';

/// Owns "what OurMynd knows about you": one short, readable profile written by
/// the AI from everything the app has seen, plus the thoughts you parked.
///
/// Three rules shape this:
///
/// * **The user can read it.** A memory that silently steers the coach and
///   cannot be inspected is a memory the user cannot trust.
/// * **The user can correct it.** [saveEdit] marks the text as hand-written,
///   and the next AI pass is told to preserve those corrections rather than
///   flatten them.
/// * **It never blocks the UI.** Refreshing is a network call; failures leave
///   the previous memory in place and surface as [error].
class MemoryProvider extends ChangeNotifier {
  MemoryProvider() {
    load();
  }

  static const _kMemory = 'om_user_memory';
  static const _kParked = 'om_parked_thoughts';
  static const _kName = 'om_preferred_name';

  /// What they asked to be called.
  ///
  /// Kept here rather than on the account because it is a preference about
  /// being addressed, not an identity: the name on your Google account is
  /// frequently not the name you want a coach using at 2am.
  String? _preferredName;
  String? get preferredName => _preferredName;

  /// True until they have either given a name or dismissed the question, so
  /// the coach asks exactly once.
  bool get needsName => _loaded && _preferredName == null;

  Future<void> setPreferredName(String name) async {
    final trimmed = name.trim();
    _preferredName = trimmed;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.setString(_kName, trimmed);
  }

  /// They would rather not say. Recorded as an empty string so we stop asking.
  Future<void> declineName() => setPreferredName('');

  /// How many parked thoughts we keep. Older ones have already been folded into
  /// the memory prose by an earlier refresh.
  static const _maxParked = 40;

  UserMemory _memory = const UserMemory();
  UserMemory get memory => _memory;

  List<ParkedThought> _parked = [];
  List<ParkedThought> get parked => List.unmodifiable(_parked);

  bool _refreshing = false;
  bool get refreshing => _refreshing;

  String? _error;
  String? get error => _error;

  bool _loaded = false;
  bool get loaded => _loaded;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kMemory);
      if (raw != null) {
        _memory = UserMemory.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      }
      _preferredName = p.getString(_kName);
      final parkedRaw = p.getString(_kParked);
      if (parkedRaw != null) {
        _parked = (jsonDecode(parkedRaw) as List)
            .map((e) => ParkedThought.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      }
    } catch (e) {
      debugPrint('[memory] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  // ─────────────────────── Parked thoughts ───────────────────────

  /// Park an intrusive thought. Returns immediately - the point of parking is
  /// that it costs nothing in the moment.
  Future<void> parkThought(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _parked.insert(
      0,
      ParkedThought(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        text: trimmed,
        at: DateTime.now(),
      ),
    );
    if (_parked.length > _maxParked) _parked = _parked.sublist(0, _maxParked);
    notifyListeners();
    await _persistParked();
  }

  Future<void> removeThought(String id) async {
    _parked.removeWhere((t) => t.id == id);
    notifyListeners();
    await _persistParked();
  }

  // ─────────────────────── The memory itself ───────────────────────

  /// The user rewrote it by hand. Their words win until they ask for a refresh.
  Future<void> saveEdit(String text) async {
    _memory = _memory.copyWith(
      text: text.trim(),
      updatedAt: DateTime.now(),
      userEdited: true,
    );
    notifyListeners();
    await _persistMemory();
  }

  Future<void> clear() async {
    _memory = const UserMemory();
    notifyListeners();
    await _persistMemory();
  }

  /// Whether the memory is old enough to be worth rewriting.
  ///
  /// Once a day, on the first open, is the right rhythm: the memory should not
  /// go stale while they keep using the app, and it should not burn a model
  /// call every time Home rebuilds. A hand-edit resets the clock like any other
  /// update, so their words get a full day before the AI folds them in.
  bool get isStale {
    if (!_loaded) return false;
    final at = _memory.updatedAt;
    if (at == null) return true;
    return DateTime.now().difference(at) > const Duration(hours: 20);
  }

  /// Ask the model to (re)write the memory from a snapshot of everything the
  /// app can see. [snapshot] is assembled by the caller because only the widget
  /// tree has the other providers to hand.
  Future<void> refresh(String snapshot) async {
    if (_refreshing) return;
    _refreshing = true;
    _error = null;
    notifyListeners();

    final parkedBlock = _parked.isEmpty
        ? 'None.'
        : _parked.take(12).map((t) => '- ${t.text}').join('\n');

    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': '''
You maintain a short profile of one user of an ADHD productivity app. The user
reads this profile themselves and it is given to their AI coach as context.

You are given everything the app has seen: their schedule and how much of it
actually happened, their goals and whether they are keeping pace, their habits,
what they say to their coach, what they park mid-focus, and what they engage
with in the community. Read across all of it, not just the task list.

Write 4-6 short sentences of plain prose, second person ("You tend to..."),
warm and specific. Cover what they are working towards, when they actually have
energy, what they keep avoiding or returning to, what is clearly weighing on
them, and anything that visibly helps. Name real things: actual goals, actual
recurring tasks, actual themes from their conversations.

No bullet points, no headings, no preamble, under 150 words.
NEVER use an em dash or en dash ("—", "–"). Use commas or full stops.

Only state things the data supports. If the data is thin, say so briefly rather
than inventing a personality.''',
      },
      {
        'role': 'user',
        'content': [
          if (_memory.text.isNotEmpty && _memory.userEdited)
            'The user has hand-edited their profile. PRESERVE their wording and '
                'any facts they added - update around them, do not contradict '
                'or delete them:\n"""\n${_memory.text}\n"""\n',
          if (_memory.text.isNotEmpty && !_memory.userEdited)
            'Current profile (rewrite and update it):\n"""\n${_memory.text}\n"""\n',
          'What the app has seen:\n$snapshot',
          '\nThoughts the user parked:\n$parkedBlock',
        ].join('\n'),
      },
    ];

    try {
      final text = await GroqService.instance.complete(messages);
      _memory = UserMemory(
        text: text.trim(),
        updatedAt: DateTime.now(),
        // The AI has now folded the edits in, so it is no longer purely the
        // user's text - but their facts survive because the prompt said so.
        userEdited: false,
      );
      await _persistMemory();
    } catch (e) {
      debugPrint('[memory] refresh failed: $e');
      _error = 'Could not update your memory just now.';
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  /// What the coach is given. Empty string when there is nothing worth sending,
  /// so the prompt builder can skip the block entirely.
  String get promptBlock {
    final named = _preferredName != null && _preferredName!.isNotEmpty;
    if (_memory.isEmpty && _parked.isEmpty && !named) return '';
    final buffer = StringBuffer();
    if (named) {
      buffer.writeln('They asked to be called $_preferredName.\n');
    }
    if (!_memory.isEmpty) {
      buffer.writeln('WHAT YOU KNOW ABOUT THIS USER:');
      buffer.writeln(_memory.text);
    }
    final recent = _parked.take(5).toList();
    if (recent.isNotEmpty) {
      buffer.writeln('\nThoughts they parked recently (do not list these back '
          'unless they bring one up):');
      for (final t in recent) {
        buffer.writeln('- ${t.text}');
      }
    }
    return buffer.toString().trim();
  }

  Future<void> _persistMemory() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMemory, jsonEncode(_memory.toJson()));
  }

  Future<void> _persistParked() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kParked, jsonEncode(_parked.map((t) => t.toJson()).toList()));
  }
}
