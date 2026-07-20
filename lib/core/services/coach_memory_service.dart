import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/chat_message.dart';

/// Manages everything that lives *between* sessions:
///
///   - **Memory summary**: a rolling 2-3 paragraph recap of all previous
///     sessions, built by asking Groq to compress prior transcripts. Stored
///     in SharedPreferences so it survives app restarts without Firebase.
///
///   - **Session history**: the raw messages from the *current* session only,
///     kept in-memory. The moment a session ends (app goes to background /
///     provider disposes), it is summarised and merged into the rolling memo.
///
/// Token budget awareness
/// ──────────────────────
/// We never send more than [maxHistoryTurns] turns to the API. Anything
/// older is compressed into the rolling summary. The summary itself is
/// capped at [_summaryCharCap] characters before we request a re-summary.
class CoachMemoryService {
  CoachMemoryService._();
  static final CoachMemoryService instance = CoachMemoryService._();

  static const _prefKey = 'om_coach_memory_summary';
  static const _prefHistKey = 'om_coach_brain_dumps';

  /// How many user+assistant turn *pairs* we keep in the live context window.
  static const maxHistoryTurns = 8; // = 16 messages

  /// If the rolling summary grows beyond this many chars, we ask Groq to
  /// compact it further before the next session starts.
  static const _summaryCharCap = 1200;

  String _memorySummary = '';
  final List<Map<String, String>> _brainDumps = [];

  // ─── Init ─────────────────────────────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _memorySummary = prefs.getString(_prefKey) ?? '';
    final raw = prefs.getString(_prefHistKey);
    if (raw != null) {
      final list = jsonDecode(raw) as List<dynamic>;
      _brainDumps.addAll(list.cast<Map<String, dynamic>>().map((m) => {
            'text': m['text'] as String,
            'at': m['at'] as String,
          }));
    }
  }

  // ─── Getters ──────────────────────────────────────────────────────────────

  String get memorySummary => _memorySummary;
  List<Map<String, String>> get brainDumps => List.unmodifiable(_brainDumps);

  bool get hasMemo => _memorySummary.isNotEmpty;

  /// Whether the summary is approaching the token budget and should be
  /// compacted before the next session.
  bool get shouldCompact => _memorySummary.length > _summaryCharCap;

  // ─── Brain dumps ──────────────────────────────────────────────────────────

  Future<void> addBrainDump(String text) async {
    final entry = {'text': text, 'at': DateTime.now().toIso8601String()};
    _brainDumps.insert(0, entry);
    if (_brainDumps.length > 10) _brainDumps.removeLast();
    await _persistDumps();
  }

  // ─── Session end ──────────────────────────────────────────────────────────

  /// Call this when the session ends (provider dispose / app pause).
  /// [turns] is the list of raw Groq-format messages from the session
  /// (not including the system / context messages).
  ///
  /// If the session was empty (no real exchange), this is a no-op.
  Future<void> finaliseSession({
    required List<Map<String, String>> turns,
    required Future<String> Function(List<Map<String, String>>) summarise,
  }) async {
    final userTurns = turns.where((m) => m['role'] == 'user').toList();
    if (userTurns.isEmpty) return;

    final transcript = turns
        .map((m) => '${m['role']?.toUpperCase()}: ${m['content']}')
        .join('\n');

    final prompt = [
      {
        'role': 'system',
        'content':
            'You are a memory assistant for an ADHD coaching app. Your job is to '
                'produce a concise, warm, 2-3 paragraph summary of what the user '
                'and their coach discussed. Focus on emotional themes, any '
                'breakthroughs, patterns noticed, and any action items the user '
                'mentioned they would try. Write in plain prose - no bullet '
                'points. Keep it under 250 words. Write in third person about '
                'the user (e.g. "they talked about…").',
      },
      {
        'role': 'user',
        'content': _memorySummary.isNotEmpty
            ? 'Previous summary:\n$_memorySummary\n\nNew session transcript:\n$transcript\n\nMerge and update the summary to include the new session.'
            : 'Session transcript:\n$transcript\n\nWrite a summary.',
      },
    ];

    try {
      final newSummary = await summarise(prompt);
      _memorySummary = newSummary.trim();
      await _persistSummary();
    } catch (_) {
      // If summarisation fails, silently skip - don't crash the app.
    }
  }

  // ─── Trim history for context window ─────────────────────────────────────

  /// Returns only the last [maxHistoryTurns] turn pairs from [allMessages]
  /// (ChatMessage list). Trims older exchanges first.
  List<ChatMessage> trimMessages(List<ChatMessage> allMessages) {
    final max = maxHistoryTurns * 2;
    if (allMessages.length <= max) return allMessages;
    return allMessages.sublist(allMessages.length - max);
  }

  /// Returns only the last [maxHistoryTurns] turn pairs from [allTurns]
  /// (Groq-format Map list). Legacy helper - prefer [trimMessages].
  List<Map<String, String>> trimHistory(List<Map<String, String>> allTurns) {
    final maxMessages = maxHistoryTurns * 2;
    if (allTurns.length <= maxMessages) return allTurns;
    return allTurns.sublist(allTurns.length - maxMessages);
  }

  // ─── Persistence ──────────────────────────────────────────────────────────

  Future<void> _persistSummary() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, _memorySummary);
  }

  Future<void> _persistDumps() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefHistKey, jsonEncode(_brainDumps));
  }

  Future<void> clearAll() async {
    _memorySummary = '';
    _brainDumps.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKey);
    await prefs.remove(_prefHistKey);
  }
}
