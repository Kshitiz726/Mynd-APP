import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/chat_message.dart';
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
  final String _userName;

  // final _groq = GroqService.instance; // swapped for Puter.js (free, in-app)
  final _ai = PuterService.instance;
  final _memory = CoachMemoryService.instance;
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

  Future<void> _init() async {
    await _memory.init();
    _messages.add(ChatMessage.welcome(_userName));
    notifyListeners();
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
        userName: _userName,
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
          assistantMsg.text += chunk.replaceAll('—', '-');
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

    // Summarise this session in the background before we go.
    final sessionTurns = _messages
        .where((m) => !m.isStreaming && m.id != 'welcome')
        .map((m) => m.toGroqMessage())
        .toList();

    unawaited(
      _memory.finaliseSession(
        turns: sessionTurns,
        summarise: _ai.complete,
      ),
    );

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
