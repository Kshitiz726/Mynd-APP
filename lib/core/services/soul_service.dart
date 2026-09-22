import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import 'groq_service.dart';

/// Who the coach is when it talks, and how that changes for one person.
///
/// The third of the app's three documents, and the one that was missing.
/// `memory.md` is what the coach remembers. The feed instructions are what it
/// brings them. This is the one that decides whether any of that lands like a
/// person said it or like a form letter.
///
/// Kept as a document rather than as prompt constants for the same reason the
/// other two are: it is meant to change. Someone who writes in fragments at 2am
/// should not be answered in the register of someone writing full sentences on
/// a Tuesday morning, and the only way to know which they are is to watch how
/// they actually write.
class SoulService {
  SoulService._();
  static final SoulService instance = SoulService._();

  static const _asset = 'assets/soul/SOUL.md';
  static const _kText = 'om_soul_text';
  static const _kSeen = 'om_soul_seen';
  static const _kAdaptedAt = 'om_soul_adapted_at';

  String _base = '';
  String _learned = '';
  final List<String> _seen = [];

  /// The shipped document, as written.
  String get base => _base;

  /// What has been noticed about this person's way of talking, if anything.
  String get learned => _learned;

  Future<void> init() async {
    try {
      _base = await rootBundle.loadString(_asset);
    } catch (e) {
      // The app must still talk if the asset is missing from a build.
      debugPrint('[soul] could not load $_asset: $e');
      _base = '';
    }
    try {
      final p = await SharedPreferences.getInstance();
      _learned = p.getString(_kText) ?? '';
      _seen
        ..clear()
        ..addAll(p.getStringList(_kSeen) ?? const []);
    } catch (e) {
      debugPrint('[soul] could not restore: $e');
    }
  }

  /// Drop what is held and re-read, for an account switch.
  Future<void> reload() async {
    _learned = '';
    _seen.clear();
    await init();
  }

  /// The block that goes into every prompt.
  ///
  /// Trimmed to the parts a model can act on. The document is written to be
  /// read by a person too, and the prose explaining *why* a rule exists is
  /// worth its space on disk and not worth its tokens in every single turn.
  String get promptBlock {
    if (_base.isEmpty && _learned.isEmpty) return '';
    final b = StringBuffer()
      ..writeln('HOW TO BE (this is the voice, and it overrides any habit)')
      ..writeln(_condense(_base));
    if (_learned.trim().isNotEmpty) {
      b
        ..writeln()
        ..writeln('WHAT YOU HAVE LEARNED ABOUT HOW THIS PERSON TALKS')
        ..writeln(_learned.trim());
    }
    return b.toString().trim();
  }

  /// Strip the document down to its instructions.
  ///
  /// Headings, table rows and bullets survive; the explanatory paragraphs and
  /// the markdown furniture do not. A full copy of the document in every turn
  /// would be most of a short conversation's budget spent on prose the model
  /// does not need to be persuaded by.
  @visibleForTesting
  static String condenseForTest(String md) => _condense(md);

  static String _condense(String md) {
    final out = <String>[];
    for (final raw in md.split('\n')) {
      final line = raw.trimRight();
      if (line.isEmpty) continue;
      if (line.startsWith('---')) continue;
      if (line.startsWith('# ')) continue;
      if (line.startsWith('|') && line.contains('---')) continue;
      if (line.startsWith('## ')) {
        out.add('');
        out.add(line.substring(3).toUpperCase());
        continue;
      }
      if (line.startsWith('|')) {
        final cells = line
            .split('|')
            .map((c) => c.trim())
            .where((c) => c.isNotEmpty)
            .toList();
        if (cells.length >= 2) out.add('- ${cells[0]}: ${cells[1]}');
        continue;
      }
      if (line.startsWith('- ') || line.startsWith('**')) {
        out.add(line.replaceAll('**', ''));
        continue;
      }
      out.add(line.replaceAll('**', ''));
    }
    return out.join('\n').trim();
  }

  /// Note how they write. Their own words only, and only enough to see a shape.
  Future<void> noteUserMessage(String raw) async {
    final t = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t.length < 8) return;
    _seen.add(t.length > 240 ? '${t.substring(0, 240)}…' : t);
    while (_seen.length > 30) {
      _seen.removeAt(0);
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kSeen, _seen);
    } catch (_) {/* the next turn will try again */}
  }

  /// Fold how they talk into the document.
  ///
  /// Rate limited hard, and deliberately conservative: a voice that is rewritten
  /// every evening is one that never settles into anything, and somebody having
  /// one unusual night should not permanently change how their coach speaks to
  /// them. Only patterns seen more than once survive.
  Future<void> adapt() async {
    if (_seen.length < 8) return;
    SharedPreferences p;
    try {
      p = await SharedPreferences.getInstance();
    } catch (_) {
      return;
    }
    final last = DateTime.tryParse(p.getString(_kAdaptedAt) ?? '');
    if (last != null && DateTime.now().difference(last).inHours < 20) return;

    try {
      final out = await GroqService.instance.extract([
        {
          'role': 'system',
          'content': '''
You watch how one person writes to their coach, and keep a short note on how
the coach should sound back at them. You are not describing their life, their
problems or their mood. Only the register: length, punctuation, humour,
directness, the words they use for things.

Rules:
- At most 6 short lines. Under 120 words total.
- Only patterns that show up more than once. One unusual evening is not a
  pattern.
- Never anything about self-harm, crisis or safety. That is not a style note
  and must never be written here.
- Never a diagnosis, never a judgement about them as a person.
- Plain statements a writer could act on: "writes in fragments, answer in
  fragments", "swears constantly, match it", "does not want jokes when things
  are bad".
- Answer with the lines only, no preamble, no heading, no quotes.''',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            if (_learned.trim().isNotEmpty) 'currentNote': _learned,
            'howTheyWrite': _seen,
          }),
        },
      ]);

      final next = out.trim();
      if (next.isEmpty || next.length > 900) return;
      _learned = next;
      await p.setString(_kText, next);
      await p.setString(_kAdaptedAt, DateTime.now().toIso8601String());
      debugPrint('[soul] adapted: ${next.length} chars');
    } catch (e) {
      debugPrint('[soul] could not adapt: $e');
    }
  }
}
