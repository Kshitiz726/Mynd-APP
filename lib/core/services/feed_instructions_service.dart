import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'groq_service.dart';

/// The document that decides what the Feed is about.
///
/// It is the same idea as the coach's rolling memory, pointed at a different
/// question. Memory is "who is this person and what happened"; this is "what
/// should I be bringing them". Two documents rather than one because they get
/// used at completely different moments and a single blended blob would mean
/// the coach's sense of somebody's week leaking into a news query, and a news
/// topic leaking into how the coach talks to them.
///
/// Two things write to it, and both matter:
///
///   The user, directly, from the Feed's own editor. That is the primary
///   driver. Whatever they write survives every later revision, because a feed
///   that quietly undoes your edits is a feed you stop editing.
///
///   The coach, from what actually gets talked about in chat. Somebody who
///   spends a week asking about sleep should not have to go and tell the Feed
///   about it. [distil] is what does that, and its prompt is explicit that the
///   user's own wording is kept intact.
class FeedInstructionsService {
  FeedInstructionsService._();
  static final FeedInstructionsService instance = FeedInstructionsService._();

  static const _kText = 'om_feed_instructions';
  static const _kTopics = 'om_feed_chat_topics';
  static const _kDistilledAt = 'om_feed_distilled_at';

  /// What a brand new feed is about, until the app knows anything.
  ///
  /// Deliberately about the person rather than the news: an empty instruction
  /// document that said "world headlines" would produce exactly the doomscroll
  /// this app exists to keep people out of.
  static const defaultText =
      'My feed is here to help me get through my week.\n\n'
      'Bring me things I can act on: focus and attention research I can '
      'actually try, ways people manage ADHD day to day, sleep and energy, and '
      'one genuinely good thing that happened in the world.\n\n'
      'Keep it short and specific. No outrage, no politics, nothing designed '
      'to make me anxious.';

  String _text = defaultText;
  final List<String> _topics = [];

  /// What the Feed is currently written against.
  String get text => _text;

  /// Whether the user has ever edited it themselves.
  bool get isDefault => _text.trim() == defaultText.trim();

  /// Recent things the user said to the coach, newest last. Fed to the writer
  /// alongside [text] so this afternoon's feed can react to this morning's
  /// conversation without waiting for a distil.
  List<String> get recentTopics => List.unmodifiable(_topics);

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _text = p.getString(_kText) ?? defaultText;
    _topics
      ..clear()
      ..addAll(p.getStringList(_kTopics) ?? const []);
  }

  /// Drop what is held in memory and re-read. For an account switch, which
  /// swaps the keys under a singleton that is not rebuilt.
  Future<void> reload() async {
    _text = defaultText;
    _topics.clear();
    await init();
  }

  Future<void> save(String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    _text = v;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kText, v);
  }

  Future<void> resetToDefault() => save(defaultText);

  /// Record something the user said to the coach.
  ///
  /// Only the user's own side of the conversation, and only the first 200
  /// characters of it. The coach's replies are its own writing and say more
  /// about the model than about the person, and a whole message would put an
  /// entire brain dump into a news query.
  Future<void> noteUserMessage(String raw) async {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    // Nothing to learn from "ok", "thanks", "yes".
    if (t.length < 12) return;
    _topics.add(t.length > 200 ? '${t.substring(0, 200)}…' : t);
    while (_topics.length > 25) {
      _topics.removeAt(0);
    }
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kTopics, _topics);
  }

  /// Fold what has been talked about back into the instruction document.
  ///
  /// Rate limited to once a day and to a real amount of new material, because
  /// it costs a model call and because an instruction document that is rewritten
  /// hourly is one that never settles into anything.
  ///
  /// Never throws, and never replaces the document with something shorter than
  /// what it started from: a truncated or refused completion must not be able
  /// to erase what somebody wrote.
  Future<void> distil() async {
    if (_topics.length < 6) return;
    final p = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(p.getString(_kDistilledAt) ?? '');
    if (last != null && DateTime.now().difference(last).inHours < 20) return;

    try {
      final out = await GroqService.instance.extract([
        {
          'role': 'system',
          'content':
              'You maintain a short document that decides what a personal news '
              'feed covers. Rewrite it so it also reflects what the person has '
              'actually been talking about.\n\n'
              'Rules:\n'
              '- Keep every interest the current document already states. The '
              'person wrote it and it is theirs.\n'
              '- Add at most two new interests, and only ones the messages '
              'show up more than once.\n'
              '- Drop nothing unless the messages say plainly it is over.\n'
              '- Plain sentences. Under 140 words. No headings, no bullet '
              'characters, no preamble, no quotes around it.\n'
              '- Answer with the document only.',
        },
        {
          'role': 'user',
          'content': 'Current document:\n$_text\n\n'
              'Recent messages from this person:\n'
              '${_topics.map((t) => '- $t').join('\n')}',
        },
      ]);

      final next = out.trim();
      // A short answer here is a failed answer, not a tidier document.
      if (next.length < _text.length * 0.6 || next.length < 60) return;
      await save(next);
      await p.setString(_kDistilledAt, DateTime.now().toIso8601String());
    } catch (e) {
      debugPrint('[feed] could not distil instructions: $e');
    }
  }

  /// Search terms for the news fetch, derived from the instructions.
  ///
  /// Asks the model, and falls back to the document's own first line. The
  /// fallback matters more than it looks: a feed whose queries depend on a
  /// model call is a feed that is empty whenever that call fails.
  Future<List<String>> searchQueries() async {
    try {
      final out = await GroqService.instance.extract([
        {
          'role': 'system',
          'content':
              'Turn a description of what someone wants in their feed into 3 '
              'news search queries. Each 2 to 5 words, no quotes, no numbering. '
              'Answer as JSON only: {"queries":["...","...","..."]}',
        },
        {'role': 'user', 'content': _text},
      ]);
      final j = jsonDecode(_jsonSlice(out)) as Map<String, dynamic>;
      final qs = ((j['queries'] as List?) ?? const [])
          .whereType<String>()
          .map((q) => q.trim())
          .where((q) => q.isNotEmpty && q.length < 60)
          .take(3)
          .toList();
      if (qs.isNotEmpty) return qs;
    } catch (e) {
      debugPrint('[feed] could not build queries: $e');
    }
    return [_fallbackQuery()];
  }

  String _fallbackQuery() {
    final first = _text.split(RegExp(r'[.\n]')).firstWhere(
          (l) => l.trim().length > 12,
          orElse: () => 'focus and attention',
        );
    final words = first
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !_stop.contains(w))
        .take(4)
        .join(' ');
    return words.isEmpty ? 'focus and attention' : words;
  }

  static const _stop = {
    'feed', 'want', 'help', 'that', 'this', 'with', 'from', 'about', 'they',
    'here', 'them', 'have', 'week', 'through', 'actually', 'things', 'bring',
  };

  /// Models wrap JSON in prose and fences more often than not. Take what is
  /// between the outermost braces and let the decoder judge it.
  static String _jsonSlice(String s) {
    final a = s.indexOf('{');
    final b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return s;
    return s.substring(a, b + 1);
  }
}
