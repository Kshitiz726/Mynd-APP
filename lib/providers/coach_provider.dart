import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../core/services/api_client.dart';
import '../core/services/api_config.dart';
import '../core/services/coach_context_builder.dart';
import '../core/services/coach_memory_service.dart';
import '../core/services/coach_prompt_builder.dart';
// import '../core/services/groq_service.dart'; // replaced by Puter.js (in-app WebView bridge)
import '../core/services/puter_service.dart';
import 'energy_provider.dart';
import 'focus_provider.dart';
import 'habit_provider.dart';
import 'health_consent_provider.dart';
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

  /// True when the server has refused this turn because today's free-tier
  /// budget is spent. Drives the paywall, and is cleared by an upgrade or by
  /// the next local midnight.
  bool _limitReached = false;
  bool get limitReached => _limitReached;

  /// How many turns are left today, as the *server* counts them. Null means
  /// unlimited (premium) or not yet known.
  int? _remainingToday;
  int? get remainingToday => _remainingToday;

  /// Ask the server where this account stands, without spending a turn.
  ///
  /// Called when the coach screen opens so the composer shows the right state
  /// immediately rather than after the user hits a wall.
  Future<void> refreshQuota() async {
    if (ApiConfig.instance.authToken == null) return;
    try {
      final j = await ApiClient.instance.coachQuota();
      final premium = j['premium'] == true;
      _remainingToday = premium ? null : (j['remaining'] as int?);
      _limitReached = !premium && (_remainingToday ?? 1) <= 0;
      notifyListeners();
    } catch (_) {
      // A quota we cannot read must not lock the composer: the turn itself is
      // still checked server side, so the worst case is one refused send with
      // a clear message rather than a coach that looks broken while offline.
    }
  }

  /// Whether health-related information may be sent to, or kept by, the coach.
  ///
  /// Everything downstream of this is one of two things: context the model is
  /// given, or memory written from what was said. Both are gated on it.
  bool get _healthConsent => HealthConsentProvider.instance.granted;

  // ─── State ────────────────────────────────────────────────────────────────

  final List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<String>? _streamSub;
  Completer<String>?
      _turnDone; // completes with the full reply when a turn ends

  // ─── Getters ──────────────────────────────────────────────────────────────

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;

  /// How many messages the user has sent in this conversation.
  int get userTurns => _messages.where((m) => m.fromUser).length;

  /// How many messages the user has sent *today* (device-local date). Drives the
  /// free tier's daily cap - counted across conversations and persisted, so
  /// starting a new chat doesn't reset the budget. Rolls over at midnight.
  int get messagesSentToday => _dailyDate == _todayKey() ? _dailyCount : 0;

  String? get errorMessage => _errorMessage;

  /// True while the last assistant message is still streaming.
  bool get isStreaming => _messages.isNotEmpty && _messages.last.isStreaming;

  int _completedTurns = 0;

  /// How many exchanges have finished this session. Watched by the memory
  /// autopilot: what you say to the coach is the richest thing the app hears
  /// all day, and it used to reach the profile only if you happened to open
  /// Home the next morning.
  int get completedTurns => _completedTurns;

  // ─── Init ─────────────────────────────────────────────────────────────────

  // ─── Persistence ──────────────────────────────────────────────────────────

  static const _kLog = 'om_coach_log';

  /// Past conversations, newest last on disk and newest first in [threads].
  static const _kThreads = 'om_coach_threads';

  /// Daily free-tier message budget: "{date}|{count}". Reset by comparing the
  /// stored date to today rather than by a timer.
  static const _kDaily = 'om_coach_daily';
  String _dailyDate = '';
  int _dailyCount = 0;

  /// The device-local calendar day as a stable key.
  static String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  Future<void> _bumpDailyCount() async {
    final today = _todayKey();
    if (_dailyDate != today) {
      _dailyDate = today;
      _dailyCount = 0;
    }
    _dailyCount++;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kDaily, '$_dailyDate|$_dailyCount');
    } catch (e) {
      debugPrint('[coach] daily count save failed: $e');
    }
    notifyListeners();
  }

  /// How many past conversations we keep. A coach history is a comfort, not an
  /// archive; past this the older ones have already been folded into the
  /// rolling memory anyway, so the words are gone but the person is not.
  static const _threadCap = 40;

  final List<CoachThread> _threads = [];

  /// Past conversations, most recent first.
  List<CoachThread> get threads => List.unmodifiable(_threads.reversed);

  /// True when the live conversation has nothing in it but the greeting, so
  /// the screen can lead with the orb rather than one lonely bubble.
  bool get isFresh =>
      _messages.where((m) => m.id != 'welcome' && !m.isStreaming).isEmpty;

  /// Put the current conversation away and start an empty one.
  ///
  /// Called every time the coach is opened. Landing in the middle of yesterday
  /// afternoon is disorienting, and scrolling up to find where you left off is
  /// worse; a new chat with the history one tap below is the honest default.
  /// An already-empty chat is left alone, so opening the coach twice in a row
  /// does not stack blank threads in the history.
  Future<void> startNewChat() async {
    if (isFresh) return;
    _archiveCurrent();
    _messages
      ..clear()
      ..add(ChatMessage.welcome(_name));
    _sinceCondense = 0;
    notifyListeners();
    await _persistThreads();
    await _persistLog();
  }

  /// Reopen a past conversation. The live one is put away first, so nothing is
  /// ever lost by navigating.
  Future<void> openThread(String id) async {
    final found = _threads.indexWhere((t) => t.id == id);
    if (found == -1) return;
    final thread = _threads.removeAt(found);
    _archiveCurrent();
    _messages
      ..clear()
      ..addAll(thread.messages);
    _sinceCondense = 0;
    notifyListeners();
    await _persistThreads();
    await _persistLog();
  }

  Future<void> deleteThread(String id) async {
    _threads.removeWhere((t) => t.id == id);
    notifyListeners();
    await _persistThreads();
  }

  void _archiveCurrent() {
    if (isFresh) return;
    final keep = _messages.where((m) => !m.isStreaming).toList();
    _threads.add(CoachThread(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      messages: keep,
      updatedAt: DateTime.now(),
    ));
    if (_threads.length > _threadCap) {
      _threads.removeRange(0, _threads.length - _threadCap);
    }
  }

  Future<void> _persistThreads() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kThreads, jsonEncode(_threads.map((t) => t.toJson()).toList()));
    } catch (e) {
      debugPrint('[coach] thread save failed: $e');
    }
  }

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
      final rawThreads = p.getString(_kThreads);
      if (rawThreads != null) {
        _threads.addAll((jsonDecode(rawThreads) as List).map(
            (t) => CoachThread.fromJson((t as Map).cast<String, dynamic>())));
      }
      final daily = p.getString(_kDaily);
      if (daily != null && daily.contains('|')) {
        final parts = daily.split('|');
        _dailyDate = parts[0];
        _dailyCount = int.tryParse(parts[1]) ?? 0;
      }
      final raw = p.getString(_kLog);
      if (raw == null) return;
      _messages.addAll((jsonDecode(raw) as List).map(
          (m) => ChatMessage.fromJson((m as Map).cast<String, dynamic>())));
    } catch (e) {
      debugPrint('[coach] restore failed: $e');
    }
  }

  Future<void> _persistLog() async {
    try {
      final keep = _messages.where((m) => !m.isStreaming).toList();
      final trimmed =
          keep.length > _logCap ? keep.sublist(keep.length - _logCap) : keep;
      final p = await SharedPreferences.getInstance();
      await p.setString(
          _kLog, jsonEncode(trimmed.map((m) => m.toJson()).toList()));
    } catch (e) {
      debugPrint('[coach] save failed: $e');
    }
  }

  /// The last few exchanges in plain text, for the memory snapshot. This is how
  /// what they actually say to the coach reaches the profile the coach reads.
  String recentTranscript({int turns = 12}) {
    final real =
        _messages.where((m) => !m.isStreaming && m.id != 'welcome').toList();
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
  ///
  /// Gated on consent. What this writes is a summary of what someone told a
  /// mental-health coach, which is health-related information however plainly
  /// it is phrased, and the policy's promise covers storing it as much as
  /// sending it. Without consent the conversation still happens and is still
  /// there to scroll back through - it simply is not distilled into a durable
  /// profile of the person.
  Future<void> _condense() async {
    _sinceCondense = 0;
    if (!_healthConsent) return;
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
    // Count it against today's free-tier budget (persisted, device-local day).
    unawaited(_bumpDailyCount());

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

    // Claim a turn before generating.
    //
    // The reply itself is produced by Puter inside the WebView, on the user's
    // own account, so it never reaches our server and cannot be metered by
    // watching the traffic. The entitlement is therefore checked separately,
    // and it is checked *here* rather than in the UI because the counter this
    // replaced lived in SharedPreferences and reset with app data.
    try {
      final turn = await ApiClient.instance.spendCoachTurn();
      _remainingToday = turn.premium ? null : turn.remaining;
      _limitReached = false;
    } on CoachTurnRefused {
      // Out of turns. Roll back the optimistic UI and let the screen offer the
      // paywall instead of leaving a placeholder that never fills in.
      _messages.remove(assistantMsg);
      _messages.remove(userMsg);
      _limitReached = true;
      _remainingToday = 0;
      _isLoading = false;
      notifyListeners();
      _turnDone?.complete('');
      _turnDone = null;
      return;
    } catch (_) {
      // Server unreachable. Allowed through: refusing to coach someone because
      // the meter is down is worse than the occasional uncounted turn, and the
      // count is reconciled on the next successful call.
    }

    try {
      // Build context + prompt.
      final context = _contextBuilder.build(
        energy: _energy,
        tasks: _tasks,
        habits: _habits,
        focus: _focus,
        settings: _settings,
        userName: _name,
        // Read per turn, not cached at construction. The coach provider lives
        // for the whole app session, so a consent withdrawn in Settings has to
        // take effect on the very next message rather than at the next launch.
        healthConsent: _healthConsent,
        userMemory: _userMemory,
      );

      // Get the conversation history excluding the placeholder we just added.
      final historyForPrompt = _memory.trimMessages(
        _messages.where((m) => !m.isStreaming && m.id != 'welcome').toList(),
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
    _completedTurns++;
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
  ///
  /// The persisting is what consent gates, and only that. A brain dump is
  /// usually whatever is weighing on someone, so keeping it as material for
  /// future coaching is health-related processing; writing it down for
  /// yourself is not. Callers that store the thought in the user's own notes
  /// or backlog are unaffected - this is the one path that feeds the coach.
  Future<void> logBrainDump(String text) async {
    if (!_healthConsent) return;
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

/// A conversation you have already had, kept so you can go back to it.
///
/// The title is derived rather than stored: it is the first thing the user
/// actually said, which is a better name for a conversation than anything a
/// model would invent for it, and it cannot drift out of sync with the content.
class CoachThread {
  CoachThread({
    required this.id,
    required this.messages,
    required this.updatedAt,
  });

  final String id;
  final List<ChatMessage> messages;
  final DateTime updatedAt;

  String get title {
    final first = messages.firstWhere(
      (m) => m.fromUser && m.text.trim().isNotEmpty,
      orElse: () => ChatMessage(id: '', text: '', fromUser: true),
    );
    final t = first.text.trim().replaceAll('\n', ' ');
    if (t.isEmpty) return 'a quiet one';
    return t.length > 44 ? '${t.substring(0, 44)}…' : t;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'at': updatedAt.toIso8601String(),
        'msgs': messages.map((m) => m.toJson()).toList(),
      };

  static CoachThread fromJson(Map<String, dynamic> j) => CoachThread(
        id: (j['id'] ?? '') as String,
        updatedAt:
            DateTime.tryParse((j['at'] ?? '') as String) ?? DateTime.now(),
        messages: ((j['msgs'] ?? const []) as List)
            .map(
                (m) => ChatMessage.fromJson((m as Map).cast<String, dynamic>()))
            .toList(),
      );
}
