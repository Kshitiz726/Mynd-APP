import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_message.dart';
import '../core/services/api_client.dart';
import '../core/services/api_config.dart';
import '../core/services/coach_context_builder.dart';
import '../core/services/coach_memory_service.dart';
import '../core/services/coach_prompt_builder.dart';
import '../core/services/feed_instructions_service.dart';
import '../core/services/groq_service.dart';
import '../core/services/ai/ai_router.dart';
import '../core/services/ai/chat_backend.dart';
import '../core/services/email_approval.dart';
import '../core/services/email_intent.dart';
import '../core/services/mail_service.dart';
import '../core/services/reminder_intent.dart';
import '../core/services/turn_context.dart';
import 'calendar_provider.dart';
import 'energy_provider.dart';
import 'focus_provider.dart';
import 'habit_provider.dart';
import 'health_consent_provider.dart';
import 'ai_consent_provider.dart';
import 'mood_provider.dart';
import 'reminders_provider.dart';
import 'settings_provider.dart';
import 'task_provider.dart';
import '../core/services/soul_service.dart';
import '../core/services/mail_control_intent.dart';
import '../core/services/mail_watch.dart';

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
  /// Late-bound so main.dart can build the providers in any order, and so the
  /// coach stays constructible in a test host with no reminder store.
  RemindersProvider? _reminders;

  void bindReminders(RemindersProvider r) => _reminders = r;

  /// Who is coaching, and how they have been tuned, as prompt text.
  ///
  /// Pushed in from the widget tree rather than read from a provider here: this
  /// class has no BuildContext, and a hard dependency on AgentProvider would
  /// mean every test that builds a coach has to build an agent too.
  ///
  /// Deliberately does not notify: it is read at the top of the next turn, and
  /// notifying from the build that sets it would loop.
  String _agentBlock = '';

  /// Who is coaching, by name, for the opening line.
  String _agentName = 'Mynd';

  void setAgentBlock(String block) => _agentBlock = block;

  /// The phone's calendar, for turns that ask about the day. Late-bound like
  /// the reminder store, so the coach stays constructible without one.
  CalendarProvider? _calendar;
  void bindCalendar(CalendarProvider c) => _calendar = c;

  /// Set alongside the block. Changing agent rewrites the opening line of a
  /// conversation that has not started yet, so the greeting is never from
  /// somebody who is no longer there. An exchange already under way is left
  /// alone: rewriting history would be worse than an old name in it.
  void setAgentName(String name) {
    if (_agentName == name) return;
    _agentName = name;
    if (_messages.length == 1 && _messages.first.id == 'welcome') {
      _messages[0] = ChatMessage.welcome(_name, agentName: _agentName);
      // Deferred, for the same reason as setPreferredName below: _buildChat
      // pushes the agent name in from its build method, so a plain notify
      // here lands mid-build and throws.
      _notifyWhenSafe();
    }
  }

  CoachProvider({
    required EnergyProvider energy,
    required TaskProvider tasks,
    required HabitProvider habits,
    required FocusProvider focus,
    required SettingsProvider settings,
    MoodProvider? mood,
    String userName = '',
  })  : _energy = energy,
        _mood = mood,
        _tasks = tasks,
        _habits = habits,
        _focus = focus,
        _settings = settings,
        _userName = userName {
    _init();
  }

  // ─── Dependencies ─────────────────────────────────────────────────────────

  final EnergyProvider _energy;

  /// The daily check-in. Held rather than passed per turn because it is the one
  /// piece of context the user sets by hand, and every reply has to see it.
  final MoodProvider? _mood;
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

  // Groq, reached through our own server, rather than Puter's in-app WebView
  // bridge. Puter is free, but it asks each person for a Puter account before
  // it will answer - a second signup, to a company they did not choose, in
  // front of the feature the app is named for. The server already meters and
  // authenticates this route, so the coach now needs nothing beyond being
  // signed in to OurMynd.
  final _ai = GroqService.instance;
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
      _messages[0] = ChatMessage.welcome(_name, agentName: _agentName);
      _notifyWhenSafe();
    }
  }

  /// [notifyListeners], but safe to call while the tree is building.
  ///
  /// CoachScreen pushes the preferred name and the agent name in from its
  /// `build`, and both setters rewrite the welcome line when the value
  /// arrives, so the notify landed mid-build and threw "setState() or
  /// markNeedsBuild() called during build". The chat still rendered, which is
  /// why it survived: a red screen in the log and nothing more.
  ///
  /// Deferring to the end of the frame is the standard remedy. Outside a build
  /// it notifies immediately, so nothing waits a frame for no reason.
  void _notifyWhenSafe() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
      return;
    }
    notifyListeners();
  }

  final _contextBuilder = CoachContextBuilder.instance;
  final _promptBuilder = CoachPromptBuilder.instance;

  /// True when the server has refused this turn because the week's budget is
  /// spent. Drives the paywall, and is cleared by an upgrade or by the reset.
  bool _limitReached = false;
  bool get limitReached => _limitReached;

  /// How many messages are left this week, as the *server* counts them. Null
  /// means uncapped (Pro) or not yet known.
  int? _remainingToday;
  int? get remainingToday => _remainingToday;

  /// Used and allowed this week, straight from the server. Null until a quota
  /// call has come back.
  int? _usedThisWeek;
  int? _weeklyLimit;
  DateTime? _resetsAt;

  int? get usedThisWeek => _usedThisWeek;
  int? get weeklyLimit => _weeklyLimit;

  /// When the allowance rolls over. Shown rather than implied: "you have run
  /// out" without "and it comes back on Monday" reads as permanent.
  DateTime? get quotaResetsAt => _resetsAt;

  /// True once enough of the week's budget is gone to be worth warning about.
  ///
  /// Silence until the wall, then a hard stop, is the pattern that made this
  /// feel broken. A number that appears with a fifth of the budget left gives
  /// somebody the chance to spend the rest deliberately.
  bool get quotaRunningLow {
    final limit = _weeklyLimit;
    final left = _remainingToday;
    if (limit == null || left == null) return false;
    return left <= (limit * 0.2).ceil();
  }

  /// Ask the server where this account stands, without spending a turn.
  ///
  /// Called when the coach screen opens so the composer shows the right state
  /// immediately rather than after the user hits a wall.
  Future<void> refreshQuota() async {
    if (ApiConfig.instance.authToken == null) return;
    try {
      final j = await ApiClient.instance.coachQuota();
      _weeklyLimit = j['limit'] as int?;
      _usedThisWeek = j['used'] as int?;
      _remainingToday = j['remaining'] as int?;
      _resetsAt = DateTime.tryParse((j['resetsAt'] as String?) ?? '');
      // Uncapped tiers report a null limit, and must never read as "0 left".
      _limitReached = _weeklyLimit != null && (_remainingToday ?? 1) <= 0;
      debugPrint('[coach] quota: used=$_usedThisWeek limit=$_weeklyLimit '
          'remaining=$_remainingToday locked=$_limitReached '
          'resets=$_resetsAt');
      notifyListeners();
    } catch (e) {
      debugPrint('[coach] quota check failed: $e');
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
      ..add(ChatMessage.welcome(_name, agentName: _agentName));
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
    if (_messages.isEmpty) _messages.add(ChatMessage.welcome(_name, agentName: _agentName));
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
      ..add(ChatMessage.welcome(_name, agentName: _agentName));
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

    // The floor, re-checked at the send itself, for the race where consent is
    // withdrawn in Settings while a message is being typed. Catching it here
    // means that withdrawal does not cost a metered turn on a request the
    // server is about to refuse with 403.
    //
    // Keyed on `declined`, a settled no, NOT on `!granted`. The two differ
    // only while an answer is being established, and in that window the screen
    // gate has already stopped anyone reaching the composer: it now asks as
    // soon as there is no answer on file, without waiting for the server.
    // Keying this on `!granted` would therefore add nothing except a way to
    // reject a message on a screen that should not have opened - and it was
    // exactly that, before the gate asked offline, that produced a chat which
    // opened normally and then refused every message typed into it.
    //
    // The server's 403 on /coach/completions is the real enforcement. This is
    // defence in depth for one case the screen gate cannot see: consent
    // withdrawn in Settings while a message is already being typed.
    if (AiConsentProvider.instance.declined) {
      _errorMessage = 'The coach is off until you agree to AI replies.';
      notifyListeners();
      return;
    }

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
    // What somebody keeps bringing up is what their feed should be about, and
    // making them go and type it into the feed as well would be asking the
    // same thing twice. Only their own words are kept, and only on the device.
    unawaited(FeedInstructionsService.instance.noteUserMessage(text));
    // How they write, kept separately from what they write about. The feed
    // wants the topics; the voice wants the register.
    unawaited(SoulService.instance.noteUserMessage(text));

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
    // Claimed separately from the generation, because the generation does
    // not always pass through our server: on the built-in provider it does,
    // but somebody using their own Claude or Gemini account talks to them
    // straight from the device, where there is no traffic of ours to meter.
    //
    // Checked here rather than in the UI because the counter this replaced
    // lived in SharedPreferences and reset with app data.
    // Only the built-in provider is metered, and that is what the cap is
    // for: it rations OUR inference bill. Somebody who has connected their
    // own Claude or Gemini account is paying their provider directly, so
    // spending one of our free weekly turns would cap a conversation we are
    // not paying for, and then tell them "Plus raises the limit" when Plus
    // would change nothing about it.
    if (AiRouter.instance.effective == AiProvider.groq) {
      try {
        final turn = await ApiClient.instance.spendCoachTurn();
        _remainingToday = turn.remaining;
        _usedThisWeek = turn.used ?? _usedThisWeek;
        _weeklyLimit = turn.limit;
        _limitReached = false;
      } on CoachTurnRefused {
        // Out of turns for today.
        //
        // The user's own message STAYS. Removing it was the old behaviour and it
        // was the worst possible answer: you typed a sentence, pressed send, and
        // watched it disappear with nothing said. That is indistinguishable from
        // the app being broken, and it is why this was reported as "the chat
        // doesn't work" rather than as "I ran out of messages". Words somebody
        // typed are theirs; the app does not get to take them back.
        //
        // Only the empty placeholder is replaced, with the reason, so the answer
        // is in the conversation where they are already looking rather than
        // depending on a banner elsewhere on the screen rendering correctly.
        debugPrint('[coach] turn refused: out of free messages for today');
        assistantMsg
          ..isStreaming = false
          ..text = "That's this week's messages used up. They reset "
              '${_resetsAtPhrase()}, or Plus raises the limit.';
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
        mood: _mood,
        userMemory: _userMemory,
      );

      // Get the conversation history excluding the placeholder we just added.
      final historyForPrompt = _memory.trimMessages(
        _messages.where((m) => !m.isStreaming && m.id != 'welcome').toList(),
      );

      // Inbox and calendar, but only when the turn is actually about them.
      // Fetched here rather than bundled into the standing context because
      // both are expensive and private: nobody asking for a pep talk should
      // have their last twelve emails sent to a model as a side effect.
      final extra = await gatherTurnContext(
        text,
        tasks: _tasks,
        calendar: _calendar ?? CalendarProvider(),
        focus: _focus,
      );

      final messages = _promptBuilder.build(
        context: context,
        history: historyForPrompt,
        userMessage: text,
        agentBlock: _agentBlock,
        mailConnected: MailService.instance.canSend,
        mailCanRead: MailService.instance.canRead,
        soulBlock: SoulService.instance.promptBlock,
      );
      if (!extra.isEmpty) {
        // Immediately before the user's turn, so it is the freshest thing the
        // model has when it answers the question that asked for it.
        messages.insert(
          messages.length - 1,
          {'role': 'system', 'content': extra.promptBlock},
        );
      }

      // Stream the response, through whichever provider is in play.
      //
      // This one call is the entire chat migration. Everything else the coach
      // does - the reminder and email markers, the memory summary, the agent
      // personas - rides in the message text above, so it crosses providers
      // untouched. The app's other model work (feed, goals, mood, memory,
      // soul, brain dump) deliberately does NOT come through here: it stays
      // on GroqService.extract on our own unmetered route, because those are
      // internals tuned against that model and nobody agreed to spend their
      // personal Claude quota re-ranking a feed.
      final stream = AiRouter.instance.streamCompletion(messages);
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
          debugPrint('[coach] stream failed: $e');
          if (assistantMsg.text.isEmpty) {
            assistantMsg.text = e is CoachLimitException
                ? "That's this week's messages used up. They reset "
                    '${_resetsAtPhrase()}, or Plus raises the limit.'
                // A connected provider's own words. "Anthropic rejected your
                // key" tells somebody what to do; the generic wording tells
                // them only that something broke.
                : e is ChatBackendException
                    ? e.message
                    : "That didn't go through: ${_explain(e)}";
            if (e is CoachLimitException) {
              _limitReached = true;
              _remainingToday = 0;
            }
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

          // A completed stream that produced nothing.
          //
          // Not hypothetical: these are reasoning models and the thinking comes
          // out of the same token budget as the reply, so a turn can finish
          // successfully having written no content at all. Left alone it
          // renders as an empty bubble that sits there forever, which reads as
          // the app being broken rather than as one turn failing.
          if (assistantMsg.text.trim().isEmpty) {
            debugPrint('[coach] the model returned an empty reply');
            assistantMsg.text =
                'That one came back empty on me. Say it again?';
          }
          // Only once the reply is whole. A marker arrives a few tokens at a
          // time, so acting mid-stream would read half of one and set an alarm
          // for a time the coach had not finished writing.
          _runReminderIntents(assistantMsg);
          _runMailControlIntents(assistantMsg);
          _runEmailIntents(assistantMsg);
          notifyListeners();
          _turnDone?.complete(assistantMsg.text);
          _turnDone = null;
          _afterTurn();
        },
        cancelOnError: true,
      );
    } on CoachLimitException {
      // The completions route enforces the cap too, and it can refuse even
      // when /coach/turn allowed the turn. Handled by name so it reads as
      // running out rather than as a fault.
      debugPrint('[coach] completions refused: over the weekly limit');
      assistantMsg
        ..isStreaming = false
        ..text = "That's this week's messages used up. They reset "
            '${_resetsAtPhrase()}, or Plus raises the limit.';
      _limitReached = true;
      _remainingToday = 0;
      _isLoading = false;
      notifyListeners();
      _turnDone?.complete(assistantMsg.text);
      _turnDone = null;
    } catch (e, st) {
      // Logged in full, and the reason is put in front of the user.
      //
      // "Something went wrong on my end" with the cause captured into a field
      // nothing ever reads is how one broken turn became a whole afternoon of
      // guessing. The exception text is ours, not the model's, so there is
      // nothing of the conversation in it to leak.
      debugPrint('[coach] turn failed: $e');
      debugPrintStack(stackTrace: st, label: 'coach');
      assistantMsg
        ..isStreaming = false
        ..text = "That didn't go through: ${_explain(e)}";
      _isLoading = false;
      _errorMessage = e.toString();
      notifyListeners();
      _turnDone?.complete(assistantMsg.text);
      _turnDone = null;
    }
  }

  /// Set whatever the coach just agreed to set, and hide the machinery.
  ///
  /// The marker is stripped from the message whether or not the reminder is
  /// actually created: if something goes wrong scheduling it, the user should
  /// see the coach's sentence and a failure they can act on, never a line of
  /// brackets in the middle of a conversation.
  void _runReminderIntents(ChatMessage msg) {
    final intents = parseReminderIntents(msg.text);
    if (intents.isEmpty) return;
    msg.text = stripReminderMarkers(msg.text);

    final reminders = _reminders;
    if (reminders == null) {
      // Nothing is bound in a test host or before the tree is up. Say so rather
      // than letting the coach claim it set something that went nowhere.
      debugPrint('[coach] ${intents.length} reminder(s) asked for, '
          'but no RemindersProvider is bound');
      return;
    }
    for (final i in intents) {
      debugPrint('[coach] setting reminder $i');
      reminders.add(i.toReminder());
    }
  }

  /// Send whatever the coach just agreed to send.
  ///
  /// Async and unawaited, unlike the reminder path: SMTP is a network round
  /// trip of a second or two and the reply is already on screen. Blocking the
  /// turn on it would freeze a finished message mid-conversation.
  ///
  /// The outcome is appended as its own message rather than folded into the
  /// coach's reply. Sending mail on somebody's behalf is the most consequential
  /// thing this app does, so whether it actually left has to be stated plainly
  /// and separately, not implied by a sentence the model wrote before it knew.
  @visibleForTesting
  void runEmailIntents(ChatMessage msg) => _runEmailIntents(msg);

  @visibleForTesting
  void runMailControlIntents(ChatMessage msg) => _runMailControlIntents(msg);

  /// Watching the inbox, and queueing a message for later.
  ///
  /// Neither of these sends anything now, so neither goes through the approval
  /// sheet. Queueing one does show the time it will go at, because "I'll send
  /// it later" with no stated time is how somebody ends up finding out at
  /// 3am.
  void _runMailControlIntents(ChatMessage msg) {
    final watch = parseWatchIntent(msg.text);
    final later = parseScheduleIntents(msg.text);
    if (watch == null && later.isEmpty) return;
    msg.text = stripMailControlMarkers(msg.text);

    if (watch != null) {
      unawaited(MailWatch.instance.setWatching(watch.on).then((_) {
        _say(watch.on
            ? '👀 Watching your inbox. I will tell you when something lands.'
            : '👀 Stopped watching your inbox.');
      }));
    }

    for (final l in later) {
      final m = ScheduledMail(
        id: 's-${DateTime.now().microsecondsSinceEpoch}-${l.to.hashCode}',
        to: l.to,
        subject: l.subject,
        body: l.body,
        at: l.at,
      );
      unawaited(MailWatch.instance.scheduleSend(m).then((_) {
        _say('🕒 Queued for ${_whenPhrase(l.at)}, to ${l.to}.');
      }));
    }
  }

  /// "today at 18:30", "tomorrow at 09:00", "on 24/9 at 09:00".
  static String _whenPhrase(DateTime at) {
    final now = DateTime.now();
    final hh = at.hour.toString().padLeft(2, '0');
    final mm = at.minute.toString().padLeft(2, '0');
    final sameDay = at.year == now.year && at.month == now.month && at.day == now.day;
    final tomorrow = at.difference(DateTime(now.year, now.month, now.day)).inDays == 1;
    if (sameDay) return 'today at $hh:$mm';
    if (tomorrow) return 'tomorrow at $hh:$mm';
    return 'on ${at.day}/${at.month} at $hh:$mm';
  }

  void _runEmailIntents(ChatMessage msg) {
    final intents = parseEmailIntents(msg.text);
    if (intents.isEmpty) return;
    msg.text = stripEmailMarkers(msg.text);

    // The same message twice is one message.
    //
    // A model that has been told to write a marker will now and then write it
    // twice in one reply, once mid-sentence and once at the end as a summary.
    // Nothing downstream could tell that apart from somebody genuinely asking
    // for two emails, so the recipient got two identical messages and the
    // conversation reported it twice.
    final seen = <String>{};
    final unique = [
      for (final i in intents)
        if (seen.add('${i.to}\u0000${i.subject}\u0000${i.body}')) i,
    ];
    if (unique.length != intents.length) {
      debugPrint('[coach] dropped ${intents.length - unique.length} '
          'duplicate email intent(s)');
    }
    unawaited(_sendAll(unique));
  }

  // ─── Approving a send ─────────────────────────────────────────────────────

  static const _kAlwaysSend = 'om_mail_always_send';

  EmailIntent? _pendingEmail;
  Completer<EmailDecision>? _emailDecision;
  bool _alwaysSend = false;

  /// The email waiting on an answer, or null. The chat screen watches this and
  /// puts the approval sheet up.
  EmailIntent? get pendingEmail => _pendingEmail;

  /// They have said "never ask again". Shown in settings so it can be undone.
  bool get alwaysSendMail => _alwaysSend;

  StreamSubscription<List<MailSummary>>? _arrivals;
  StreamSubscription<SentResult>? _queuedSends;

  /// Listen for mail landing and for queued messages going out.
  ///
  /// The coach says these itself rather than the app showing a banner, because
  /// the whole promise of the watch is that somebody hears about their mail
  /// from the same voice they asked to watch it.
  void bindMailWatch() {
    _arrivals ??= MailWatch.instance.arrivals.listen((fresh) {
      if (fresh.isEmpty) return;
      _say(_arrivalLine(fresh));
    });
    _queuedSends ??= MailWatch.instance.sends.listen((r) {
      _say(r.ok
          ? '✉️ Sent that one to ${r.mail.to} as planned.'
          : "✉️ The one for ${r.mail.to} didn't go. ${r.message}");
    });
  }

  /// What just arrived, in a sentence rather than a header dump.
  ///
  /// Written here rather than asked of the model on purpose: this fires when
  /// nobody is necessarily looking, and spending a model call and a second of
  /// latency to announce two emails would be the wrong trade. The subject line
  /// is the publisher's own summary of itself and is usually enough.
  static String _arrivalLine(List<MailSummary> fresh) {
    if (fresh.length == 1) {
      final m = fresh.first;
      final subject = m.subject.trim();
      return '📬 ${m.from} just emailed you'
          '${subject.isEmpty ? '.' : ', about "$subject".'}';
    }
    final names = <String>{for (final m in fresh) m.from}.take(3).join(', ');
    return '📬 ${fresh.length} new emails just landed, from $names.';
  }

  Future<void> loadMailPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      _alwaysSend = p.getBool(_kAlwaysSend) ?? false;
      notifyListeners();
    } catch (e) {
      debugPrint('[coach] could not read mail prefs: $e');
    }
  }

  Future<void> setAlwaysSendMail(bool v) async {
    _alwaysSend = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kAlwaysSend, v);
    } catch (e) {
      debugPrint('[coach] could not save mail prefs: $e');
    }
  }

  /// Answer the pending approval. Called by the sheet.
  void resolvePendingEmail(EmailDecision d) {
    final c = _emailDecision;
    _emailDecision = null;
    _pendingEmail = null;
    notifyListeners();
    c?.complete(d);
  }

  /// Put an email in front of them and wait.
  ///
  /// Returns the decision. If the screen goes away without answering, the
  /// completer is never completed and the send simply never happens, which is
  /// the right way for this particular thing to fail.
  Future<EmailDecision> _askApproval(EmailIntent i) {
    final c = Completer<EmailDecision>();
    _emailDecision = c;
    _pendingEmail = i;
    notifyListeners();
    return c.future;
  }

  /// Rewrite a draft the way they asked, without sending anything.
  ///
  /// Goes through the unmetered extract route rather than the coach's own
  /// conversation budget: this is the app editing a draft on their behalf, not
  /// a message to their coach, and charging somebody a message for saying
  /// "make it shorter" would be indefensible.
  Future<EmailIntent> _reviseDraft(EmailIntent i, String instruction) async {
    try {
      final out = await GroqService.instance.extract([
        {
          'role': 'system',
          'content': 'You are editing one email before it is sent. Apply the '
              "change the sender asks for and change nothing else. Keep it in "
              'their voice, signed off as them. Never invent a fact, a name, a '
              'date or a number that is not already in the draft or in their '
              'instruction.\n\n'
              'Answer as JSON only: {"subject":"...","body":"..."}',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'to': i.to,
            'subject': i.subject,
            'body': i.body,
            'changeRequested': instruction,
          }),
        },
      ]);
      final j = jsonDecode(_jsonSlice(out)) as Map<String, dynamic>;
      final subject = (j['subject'] as String?)?.trim();
      final body = (j['body'] as String?)?.trim();
      if (subject == null || subject.isEmpty || body == null || body.isEmpty) {
        return i;
      }
      return EmailIntent(to: i.to, subject: subject, body: body);
    } catch (e) {
      // A failed rewrite returns the draft untouched rather than sending
      // something mangled or nothing at all. They see it unchanged and can
      // say so again.
      debugPrint('[coach] could not revise the draft: $e');
      return i;
    }
  }

  static String _jsonSlice(String s) {
    final a = s.indexOf('{');
    final b = s.lastIndexOf('}');
    if (a < 0 || b <= a) return s;
    return s.substring(a, b + 1).replaceAll(RegExp(r'[\x00-\x1F]'), ' ');
  }

  /// Send what the coach agreed to send, and say what happened either way.
  ///
  /// Awaited to completion per message, and reported per message. A send that
  /// fails silently is the worst outcome available here: the reply above it
  /// already reads as though the mail went, so saying nothing actively tells
  /// somebody a message was delivered when it was not.
  Future<void> _sendAll(List<EmailIntent> intents) async {
    for (final original in intents) {
      final approved = await _approve(original);
      if (approved == null) continue;
      await _sendOne(approved);
    }
  }

  /// Put a draft in front of them until they settle it.
  ///
  /// Returns the email to send, or null if they said no. The loop is what
  /// makes "change something" work: a revision is a new draft, and a new draft
  /// gets approved on its own terms, as many times as they like.
  Future<EmailIntent?> _approve(EmailIntent draft) async {
    if (_alwaysSend) return draft;

    var current = draft;
    while (true) {
      final d = await _askApproval(current);
      switch (d.kind) {
        case EmailApproval.allow:
          return current;
        case EmailApproval.always:
          await setAlwaysSendMail(true);
          return current;
        case EmailApproval.cancel:
          _say('✉️ Not sent. Say what you want changed and I will redo it.');
          return null;
        case EmailApproval.change:
          final what = d.instruction?.trim() ?? '';
          if (what.isEmpty) continue;
          final note = _say('✉️ Rewriting that…');
          current = await _reviseDraft(current, what);
          _messages.remove(note);
          notifyListeners();
      }
    }
  }

  Future<void> _sendOne(EmailIntent i) async {
    // The address is in here; the body and the credential are not.
    debugPrint('[coach] sending mail to ${i.to}');

    // A placeholder first, because an SMTP round trip is seconds long and an
    // empty pause after "I'll send that" is indistinguishable from the feature
    // having done nothing at all. The same bubble is then edited, rather than
    // a second one being added under it.
    final note = _say('✉️ Sending to ${i.to}…');

    MailResult r;
    try {
      r = await MailService.instance.send(
        to: i.to,
        subject: i.subject,
        body: i.body,
      );
    } catch (e) {
      // send() is documented not to throw, and an unhandled exception here
      // would leave the bubble above saying "sending…" forever.
      debugPrint('[coach] send threw: $e');
      r = const MailResult.failure('Something broke while sending.');
    }

    debugPrint('[coach] send result: ok=${r.ok} ${r.message}');
    note.text = r.ok
        ? '✉️ Sent to ${i.to}.'
        : "✉️ Didn't send to ${i.to}. ${r.message}";
    notifyListeners();
  }

  /// Add a message from the coach and return it, so it can be edited in place.
  ChatMessage _say(String text) {
    final m = ChatMessage(
      id: 'm-${DateTime.now().microsecondsSinceEpoch}-${_messages.length}',
      text: text,
      fromUser: false,
    );
    _messages.add(m);
    notifyListeners();
    return m;
  }

  /// A short, plain reason. Deliberately not the raw exception: those carry
  /// stack frames and URLs, and this goes straight into a chat bubble.
  static String _explain(Object e) {
    final s = e.toString();
    if (e is GroqException) {
      final code = e.statusCode;
      if (code == null) return 'the coach could not be reached.';
      if (code == 503) return 'the coach is not configured on the server.';
      if (code == 400) return 'the server rejected that message.';
      if (code == 401 || code == 403) {
        return 'your session expired. Sign in again.';
      }
      if (code >= 500) return 'the server is having a moment. Try again shortly.';
      return 'the server answered $code.';
    }
    if (s.contains('SocketException') ||
        s.contains('Failed host lookup') ||
        s.contains('Connection')) {
      return 'no connection to the server.';
    }
    if (s.contains('TimeoutException') || s.contains('took too long')) {
      return 'the server took too long to answer.';
    }
    return 'something broke on our side, and it is now in the logs.';
  }

  /// "on Monday", or "soon" when the server did not say.
  String _resetsAtPhrase() {
    final at = _resetsAt;
    if (at == null) return 'at the start of next week';
    const days = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    return 'on ${days[at.toLocal().weekday - 1]}';
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
    // Rate limited to once a day inside the service, so this is cheap to call
    // after every turn and means the voice keeps up with how somebody has
    // started talking rather than how they talked the week they signed up.
    unawaited(SoulService.instance.adapt());
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
    await _arrivals?.cancel();
    await _queuedSends?.cancel();
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
