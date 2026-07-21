import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../core/services/api_config.dart';
import '../core/services/coach_context_builder.dart';
import '../core/services/coach_memory_service.dart';
import '../core/services/coach_prompt_builder.dart';
// import '../core/services/groq_service.dart'; // replaced by Puter.js (in-app WebView bridge)
import '../core/services/puter_service.dart';
import 'energy_provider.dart';
import 'focus_provider.dart';
import 'habit_provider.dart';
import 'settings_provider.dart';
import 'task_provider.dart';

/// The single source of truth for the coaching chat.
///
/// Responsibilities:
///   • Owns the in-session message list
///   • Orchestrates context → prompt → Groq → stream → UI
///   • Triggers memory finalisation on dispose
///   • Exposes loading / error state to the UI
///
/// Architecture
/// ────────────
///   CoachProvider
///     ├─ CoachContextBuilder  reads providers → CoachContext
///     ├─ CoachPromptBuilder   CoachContext + history → Groq messages
///     ├─ GroqService          Groq messages → SSE stream
///     └─ CoachMemoryService   persistence (summary + brain dumps)
class CoachProvider extends ChangeNotifier {
  CoachProvider({
    required EnergyProvider energy,
    required TaskProvider tasks,
    required HabitProvider habits,
    required FocusProvider focus,
    required SettingsProvider settings,
    String userName = '',
  })  : _energy = energy,
        _tasks = tasks,
        _habits = habits,
        _focus = focus,
        _settings = settings,
        _userName = userName {
    _init();
  }

  // ─── Dependencies ─────────────────────────────────────────────────────────

  final EnergyProvider _energy;
  final TaskProvider _tasks;
  final HabitProvider _habits;
  final FocusProvider _focus;
  final SettingsProvider _settings;

  /// The account name, used only as a fallback. What the user asked to be
  /// called always wins, and neither is ever invented.
  final String _userName;

  String? _preferredName;

  /// The name the coach may actually use. Empty means "we do not know", and the
  /// prompt is explicit that an unknown name must stay unknown rather than
  /// being guessed at.
  String get _name {
    final p = _preferredName;
    if (p != null) return p; // may be '' - they declined, and that is an answer
    if (_userName.isNotEmpty) return _userName;
    return ApiConfig.instance.displayName ?? '';
  }

  // final _groq = GroqService.instance; // swapped for Puter.js (free, in-app)
  final _ai = PuterService.instance;
  final _memory = CoachMemoryService.instance;

  /// The user's editable memory, pushed in from the widget tree. Kept as a
  /// plain string so the coach does not have to depend on another provider.
  String _userMemory = '';
  void setUserMemory(String value) {
    if (value == _userMemory) return;
    _userMemory = value;
  }

  /// Pushed in from the widget tree when the user tells us what to call them.
  /// If nothing has been said yet, the opening line is rewritten in place so
  /// they are greeted properly rather than by a stale "hey".
  void setPreferredName(String? value) {
    if (value == _preferredName) return;
    _preferredName = value;
    if (_messages.length == 1 && _messages.first.id == 'welcome') {
      _messages[0] = ChatMessage.welcome(_name);
      notifyListeners();
    }
  }
  final _contextBuilder = CoachContextBuilder.instance;
  final _promptBuilder = CoachPromptBuilder.instance;

  // ─── State ────────────────────────────────────────────────────────────────

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<String>? _streamSub;
  Completer<String>? _turnDone; // completes with the full reply when a turn ends

  // ─── Getters ──────────────────────────────────────────────────────────────

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// True while the last assistant message is still streaming.
  bool get isStreaming => _messages.isNotEmpty && _messages.last.isStreaming;

  // ─── Init ─────────────────────────────────────────────────────────────────

  // ─── Persistence ──────────────────────────────────────────────────────────

  static const _kLog = 'om_coach_log';

  /// How much verbatim conversation we keep on disk. Everything older has
  /// already been folded into the rolling summary, so it is not lost, just no
  /// longer quoted word for word.
  static const _logCap = 120;

  /// How many messages can accumulate before we fold the conversation into the
  /// long-term memory. The coach lives for the whole app session, so waiting
  /// for dispose meant most conversations were never remembered at all.
  static const _condenseEvery = 8;

  int _sinceCondense = 0;

  Future<void> _init() async {
    await _memory.init();
    await _restore();
    if (_messages.isEmpty) _messages.add(ChatMessage.welcome(_name));
    notifyListeners();
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kLog);
      if (raw == null) return;
      _messages.addAll((jsonDecode(raw) as List)
          .map((m) => ChatMessage.fromJson((m as Map).cast<String, dynamic>())));
    } catch (e) {
      debugPrint('[coach] restore failed: $e');
    }
  }

  Future<void> _persistLog() async {
    try {
      final keep = _messages.where((m) => !m.isStreaming).toList();
      final trimmed = keep.length > _logCap ? keep.sublist(keep.length - _logCap) : keep;
      final p = await SharedPreferences.getInstance();
      await p.setString(_kLog, jsonEncode(trimmed.map((m) => m.toJson()).toList()));
    } catch (e) {
      debugPrint('[coach] save failed: $e');
    }
  }

  /// The last few exchanges in plain text, for the memory snapshot. This is how
  /// what they actually say to the coach reaches the profile the coach reads.
  String recentTranscript({int turns = 12}) {
    final real = _messages.where((m) => !m.isStreaming && m.id != 'welcome').toList();
    if (real.isEmpty) return '';
    final tail = real.length > turns ? real.sublist(real.length - turns) : real;
    return tail
        .map((m) => '${m.fromUser ? 'THEM' : 'YOU'}: ${m.text.trim()}')
        .join('\n');
  }

  /// Start over. The rolling summary survives, because forgetting the
  /// conversation is not the same as forgetting the person.
  Future<void> clearConversation() async {
    _messages
      ..clear()
      ..add(ChatMessage.welcome(_name));
    _sinceCondense = 0;
    notifyListeners();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kLog);
  }

  /// Fold the conversation so far into the long-term memo, in the background.
  Future<void> _condense() async {
    _sinceCondense = 0;
    final turns = _messages
        .where((m) => !m.isStreaming && m.id != 'welcome')
        .map((m) => m.toGroqMessage())
        .toList();
    if (turns.isEmpty) return;
    await _memory.finaliseSession(turns: turns, summarise: _ai.complete);
  }

  // ─── Send ─────────────────────────────────────────────────────────────────

  /// Called by the UI when the user submits a message.
  Future<void> send(String raw) async {
    final text = raw.trim();
    if (text.isEmpty || _isLoading) return;

    // Cancel any in-flight stream.
    await _streamSub?.cancel();
    _streamSub = null;

    _errorMessage = null;

    // Add user message.
    final userMsg = ChatMessage(
      id: 'u-${DateTime.now().microsecondsSinceEpoch}',
      text: text,
      fromUser: true,
    );
    _messages.add(userMsg);

    // Placeholder assistant message (streaming = true).
    final assistantMsg = ChatMessage(
      id: 'a-${DateTime.now().microsecondsSinceEpoch}',
      text: '',
      fromUser: false,
      isStreaming: true,
    );
    _messages.add(assistantMsg);

    _isLoading = true;
    notifyListeners();

    try {
      // Build context + prompt.
      final context = _contextBuilder.build(
        energy: _energy,
        tasks: _tasks,
        habits: _habits,
        focus: _focus,
        settings: _settings,
        userName: _name,
        userMemory: _userMemory,
      );

      // Get the conversation history excluding the placeholder we just added.
      final historyForPrompt = _memory.trimMessages(
        _messages
            .where((m) => !m.isStreaming && m.id != 'welcome')
            .toList(),
      );

      final messages = _promptBuilder.build(
        context: context,
        history: historyForPrompt,
        userMessage: text,
      );

      // Stream the response.
      final stream = _ai.streamCompletion(messages);
      _streamSub = stream.listen(
        (chunk) {
          // The prompt forbids dashes; this is the belt to that braces. Models
          // reach for an em dash under pressure however firmly you ask them not
          // to, and one slipping through is the single clearest tell that the
          // thing you are texting is not a person.
          assistantMsg.text += _deDash(chunk);
          notifyListeners();
        },
        onError: (Object e) {
          assistantMsg.isStreaming = false;
          _isLoading = false;
          if (assistantMsg.text.isEmpty) {
            assistantMsg.text =
                "I'm having a bit of trouble connecting right now. "
                "Give it a moment and try again.";
          }
          _errorMessage = e.toString();
          notifyListeners();
          _turnDone?.complete(assistantMsg.text);
          _turnDone = null;
        },
        onDone: () {
          assistantMsg.isStreaming = false;
          _isLoading = false;
          _streamSub = null;
          notifyListeners();
          _turnDone?.complete(assistantMsg.text);
          _turnDone = null;
          _afterTurn();
        },
        cancelOnError: true,
      );
    } catch (e) {
      assistantMsg.isStreaming = false;
      assistantMsg.text =
          "Something went wrong on my end. You can try sending that again.";
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      _turnDone?.complete(assistantMsg.text);
      _turnDone = null;
    }
  }

  /// Strips em and en dashes, keeping the sentence readable rather than just
  /// deleting the character: a dash doing a comma's job becomes a comma, and a
  /// dash doing a full stop's job becomes one.
  static String _deDash(String s) => s
      .replaceAll(' — ', ', ')
      .replaceAll(' – ', ', ')
      .replaceAll('—', ', ')
      .replaceAll('–', ', ');

  /// Housekeeping after a completed exchange: keep the log on disk, and every
  /// so often fold it into the long-term memo so the coach remembers this
  /// conversation tomorrow.
  void _afterTurn() {
    unawaited(_persistLog());
    _sinceCondense += 2;
    if (_sinceCondense >= _condenseEvery) unawaited(_condense());
  }

  /// Voice turn: send [text] and resolve with the full assistant reply once the
  /// stream finishes (the talk UI then speaks it aloud).
  Future<String> sendAndAwaitReply(String text) {
    _turnDone = Completer<String>();
    final fut = _turnDone!.future;
    send(text);
    return fut;
  }

  // ─── Quick prompts ────────────────────────────────────────────────────────

  /// Sends one of the pre-defined quick-prompt chips.
  Future<void> sendQuickPrompt(String label) => send(label);

  // ─── Brain dump ───────────────────────────────────────────────────────────

  /// Persists a brain dump so the coach can reference it in future sessions.
  Future<void> logBrainDump(String text) async {
    await _memory.addBrainDump(text);
  }

  // ─── Dispose ──────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    await _streamSub?.cancel();
    unawaited(_persistLog());
    // Anything since the last fold still deserves remembering.
    if (_sinceCondense > 0) unawaited(_condense());
    super.dispose();
  }

  // ─── Convenience factory ──────────────────────────────────────────────────

  /// Creates a [CoachProvider] reading from the widget tree's providers.
  /// Use this inside [ChangeNotifierProxyProvider5].
  static CoachProvider fromContext(BuildContext context, String userName) {
    return CoachProvider(
      energy: context.read<EnergyProvider>(),
      tasks: context.read<TaskProvider>(),
      habits: context.read<HabitProvider>(),
      focus: context.read<FocusProvider>(),
      settings: context.read<SettingsProvider>(),
      userName: userName,
    );
  }
}
