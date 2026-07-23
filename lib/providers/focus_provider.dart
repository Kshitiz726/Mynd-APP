import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/api_client.dart';
import '../core/services/api_config.dart';
import '../core/services/realtime_service.dart';
import '../models/focus/body_double.dart';
import '../models/focus/room_participant.dart';
import '../models/focus_ambience.dart';
import '../models/focus_mode.dart';
import '../models/saved_focus.dart';

class FocusProvider extends ChangeNotifier {
  FocusProvider() {
    _loadSaved();
    _loadFocusSeconds();
  }

  FocusMode? _activeMode;
  String? _activeTaskTitle;
  String _ambienceId = 'none';
  int _secondsRemaining = 0;
  int _totalSeconds = 0;
  bool _isRunning = false;
  bool _bodyDoubling = false;
  Timer? _timer;

  // ── Body-doubling matchmaking (runs silently in the background) ──
  final _rt = RealtimeService.instance;
  bool _bdActive = false; // we're looking for / matched with a partner
  bool _searchingPartner = false; // still in the queue, no match yet
  BdPartner? _partner; // the person we're paired with, once matched
  String? _partnerTask; // the work they're focusing on, if they've shared it
  bool _partnerLeft = false; // they left mid-session - shown, no auto-rematch
  String? _bdRoomId; // the shared room both partners sit in
  Timer? _bdHeartbeat;
  bool _bdWired = false;

  String? get _myUserId => ApiConfig.instance.userId;

  FocusMode? get activeMode => _activeMode;

  /// What this session is *for*, when it was started from a schedule block or a
  /// saved focus. Null for a plain "just start a timer" session.
  String? get activeTaskTitle => _activeTaskTitle;

  /// The ambience chosen for this session, and the clip that plays behind the
  /// timer (empty when "none" or when nothing was chosen).
  FocusAmbience get ambience => ambienceById(_ambienceId);
  int get secondsRemaining => _secondsRemaining;

  /// How long this session started out as, so progress rings stay honest when
  /// the length came from a task rather than the mode.
  int get totalSeconds => _totalSeconds == 0 ? 1 : _totalSeconds;
  bool get isRunning => _isRunning;
  bool get bodyDoubling => _bodyDoubling;
  bool get isActive => _activeMode != null;

  /// True while we're quietly waiting for a body-doubling partner.
  bool get searchingPartner => _searchingPartner;

  /// The matched partner (name, avatar), or null if none yet.
  BdPartner? get partner => _partner;

  /// The matched partner's name, or null if none yet.
  String? get partnerName => _partner?.name;

  /// The work the partner is focusing on, when they've shared a task.
  String? get partnerTask => _partnerTask;

  /// True once the matched partner has left mid-session. The session keeps
  /// running solo; we deliberately do NOT auto-rematch (that produced an endless
  /// "matching…"). Leaving and starting again is how you find someone new.
  bool get partnerLeft => _partnerLeft;

  /// Change the running session's scene without leaving it (the in-session
  /// drag-to-switch ambience control).
  void setAmbience(String id) {
    if (_ambienceId == id) return;
    _ambienceId = id;
    notifyListeners();
  }

  String get timeString {
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    final totalMinutes = _secondsRemaining ~/ 60;
    // A two-hour task block reads as 1:59:40, not 119:40.
    if (totalMinutes >= 60) {
      final h = totalMinutes ~/ 60;
      final m = (totalMinutes % 60).toString().padLeft(2, '0');
      return '$h:$m:$s';
    }
    return '${totalMinutes.toString().padLeft(2, '0')}:$s';
  }

  /// Start a session. [seconds] overrides the mode's length, which is how
  /// "focus on this task" runs out exactly the block's remaining time rather
  /// than a rounded-down number of whole minutes.
  void start(
    FocusMode mode,
    bool bodyDoubling, {
    String? preMatchedRoomId,
    String? preMatchedPartnerName,
    String? taskTitle,
    int? seconds,
    String ambienceId = 'none',
  }) {
    _activeMode = mode;
    _activeTaskTitle = taskTitle;
    _ambienceId = ambienceId;
    _secondsRemaining = seconds ?? mode.minutes * 60;
    _totalSeconds = _secondsRemaining;
    _bodyDoubling = bodyDoubling;
    _isRunning = true;
    _startTimer();
    notifyListeners();
    if (bodyDoubling) {
      _startBodyDoublingMatch(preMatchedRoomId: preMatchedRoomId, preMatchedPartnerName: preMatchedPartnerName);
    }
  }

  // ─────────────────── Body doubling ───────────────────

  /// Join the matchmaking queue silently. If a partner is waiting we pair right
  /// away; otherwise we stay queued in the background (no blocking UI) and get
  /// paired the moment someone else toggles body doubling. The solo pomodoro
  /// keeps running the whole time.
  Future<void> _startBodyDoublingMatch({String? preMatchedRoomId, String? preMatchedPartnerName}) async {
    _bdActive = true;
    _searchingPartner = true;
    _partner = null;
    _partnerTask = null;
    _partnerLeft = false;
    _bdRoomId = null;
    _wireBd();
    notifyListeners();

    if (preMatchedRoomId != null) {
      _onMatched(
        preMatchedPartnerName == null
            ? null
            : BdPartner(
                id: '',
                name: preMatchedPartnerName,
                initial: preMatchedPartnerName.isNotEmpty ? preMatchedPartnerName[0].toUpperCase() : '?',
                color: null),
        preMatchedRoomId,
      );
      return;
    }

    try {
      final m = await ApiClient.instance.bodyDoublingMatch();
      if (!_bdActive) return; // session ended while we were requesting
      if (m.matched && m.roomId != null) {
        _onMatched(m.partner, m.roomId!);
      }
      // else: stay searching; `bd_matched` will arrive over the socket.
    } catch (e) {
      debugPrint('[focus] body-doubling match failed: $e');
      _searchingPartner = false;
      notifyListeners();
    }
  }

  void _wireBd() {
    if (_bdWired) return;
    _bdWired = true;
    _rt.on('bd_matched', (d) {
      if (!_bdActive || _bdRoomId != null) return; // ignore stale / double match
      final partner = (d['partner'] as Map?)?.cast<String, dynamic>();
      _onMatched(partner == null ? null : BdPartner.fromJson(partner), d['roomId'] as String?);
    });
    // Presence in our shared room: pick up who the partner is and the work
    // they're on, and notice the moment they leave so we can re-match. These
    // guards no-op unless we're actually body-doubling, so they cost nothing to
    // the room feature which listens to the same events.
    _rt.on('room_state', (d) {
      if (!_bdActive || _bdRoomId == null) return;
      for (final p in (d['participants'] as List? ?? const [])) {
        _adoptPartner(RoomParticipant.fromJson((p as Map).cast()));
      }
    });
    _rt.on('participant_joined', (d) {
      if (!_bdActive || _bdRoomId == null) return;
      final pj = (d['participant'] as Map?)?.cast<String, dynamic>();
      if (pj != null) _adoptPartner(RoomParticipant.fromJson(pj));
    });
    _rt.on('participant_update', (d) {
      // In a 2-person body-doubling room the only other participant is the
      // partner, so capture their work from any non-self update - even if it
      // arrives before we've formally adopted them (which used to lose it).
      if (!_bdActive || _bdRoomId == null || d['userId'] == _myUserId) return;
      final patch = (d['patch'] as Map?)?.cast<String, dynamic>();
      final t = (patch?['session'] as Map?)?['task'] as String?;
      if (t != null && t.isNotEmpty && t != 'Focus') {
        _partnerTask = t;
        notifyListeners();
      }
    });
    _rt.on('participant_left', (d) {
      if (_partner == null || d['userId'] != _partner!.id) return;
      _onPartnerLeft();
    });
  }

  /// Adopt the other person in the room as our partner (their name, avatar, and
  /// the task they're working on, when shared).
  void _adoptPartner(RoomParticipant p) {
    if (p.userId == _myUserId) return; // that's me
    _partner = BdPartner(id: p.userId, name: p.displayName, initial: p.initial, color: p.avatarColor);
    if (p.task != null && p.task!.isNotEmpty && p.task != 'Focus') _partnerTask = p.task;
    _partnerLeft = false;
    _searchingPartner = false;
    notifyListeners();
  }

  /// The partner left mid-session. Show that they left, keep our own timer
  /// running, and stop there - no auto-rematch (which produced an endless
  /// "matching…"). Finding someone new is a deliberate "go back and start
  /// again", nothing automatic.
  void _onPartnerLeft() {
    _partnerLeft = true;
    _searchingPartner = false;
    notifyListeners();
  }

  void _onMatched(BdPartner? partner, String? roomId) {
    if (roomId == null || _bdRoomId != null) return;
    _bdRoomId = roomId;
    _partner = partner;
    _partnerLeft = false;
    _searchingPartner = false;
    // Sit both partners in the same room and share the pomodoro - with our real
    // task, so each side sees what the other is working on. The room
    // auto-closes when both leave.
    _rt.joinRoom(roomId);
    final mode = _activeMode;
    if (mode != null) {
      _rt.setSession(roomId,
          task: _activeTaskTitle ?? 'Focus', mode: mode.serverMode, durationSecs: _secondsRemaining);
    }
    _bdHeartbeat?.cancel();
    _bdHeartbeat = Timer.periodic(const Duration(seconds: 25), (_) => _rt.heartbeat(roomId));
    notifyListeners();
  }

  /// Tear down matchmaking: leave the queue if still waiting, leave the shared
  /// room if paired (the server auto-closes it once empty), and clear state.
  void _endBodyDoubling() {
    if (!_bdActive) return;
    _bdActive = false;
    _bdHeartbeat?.cancel();
    _bdHeartbeat = null;
    final roomId = _bdRoomId;
    if (roomId != null) {
      _rt.leaveRoom(roomId);
    } else if (_searchingPartner) {
      ApiClient.instance.bodyDoublingCancel().catchError((_) {});
    }
    _bdRoomId = null;
    _partner = null;
    _partnerTask = null;
    _partnerLeft = false;
    _searchingPartner = false;
  }

  void togglePause() {
    _isRunning = !_isRunning;
    if (_isRunning) {
      _startTimer();
    } else {
      _timer?.cancel();
    }
    notifyListeners();
  }

  // ─────────────────── Saved focuses ───────────────────

  List<SavedFocus> _saved = [];
  List<SavedFocus> get savedFocuses => List.unmodifiable(_saved);

  static const _kSaved = 'om_saved_focuses';

  Future<void> _loadSaved() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kSaved);
      if (raw == null) return;
      _saved = (jsonDecode(raw) as List)
          .map((e) => SavedFocus.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('[focus] saved focuses failed to load: $e');
    }
  }

  Future<void> _persistSaved() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kSaved, jsonEncode(_saved.map((f) => f.toJson()).toList()));
  }

  SavedFocus addSavedFocus({required String name, required int minutes, String iconName = 'target'}) {
    final focus = SavedFocus(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: name,
      minutes: minutes,
      iconName: iconName,
    );
    // Newest first: the thing you just made is the thing you are about to do.
    _saved.insert(0, focus);
    _persistSaved();
    notifyListeners();
    return focus;
  }

  void removeSavedFocus(String id) {
    _saved.removeWhere((f) => f.id == id);
    _persistSaved();
    notifyListeners();
  }

  void end() {
    _timer?.cancel();
    // The session is over, so bank the seconds now rather than waiting out the
    // debounce - ending a focus is exactly when someone closes the app.
    _focusSaveDebounce?.cancel();
    _focusSaveDebounce = null;
    _persistFocusSeconds();
    _endBodyDoubling();
    _activeMode = null;
    _activeTaskTitle = null;
    _ambienceId = 'none';
    _isRunning = false;
    _secondsRemaining = 0;
    _bodyDoubling = false;
    notifyListeners();
  }

  // ─────────────── Time actually spent focusing ───────────────
  //
  // Home used to report this as the sum of the scheduled durations of every
  // task ticked off, so checking eight one-hour blocks claimed "8h focused"
  // even if the timer had never run. That is not a statistic, it is flattery.
  // This counts real seconds, one per tick, only while the clock is running.

  static const _kFocusSeconds = 'om_focus_seconds';

  /// Seconds focused, keyed by 'yyyy-mm-dd'.
  Map<String, int> _focusedByDay = {};

  static String _dayKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// Real time on the clock today.
  Duration get focusedToday =>
      Duration(seconds: _focusedByDay[_dayKey(DateTime.now())] ?? 0);

  Duration focusedOn(DateTime day) =>
      Duration(seconds: _focusedByDay[_dayKey(day)] ?? 0);

  Timer? _focusSaveDebounce;

  void _countSecond() {
    final key = _dayKey(DateTime.now());
    _focusedByDay[key] = (_focusedByDay[key] ?? 0) + 1;
    // One disk write a second would be absurd; the loss window is 10s.
    _focusSaveDebounce ??= Timer(const Duration(seconds: 10), () {
      _focusSaveDebounce = null;
      _persistFocusSeconds();
    });
  }

  Future<void> _loadFocusSeconds() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kFocusSeconds);
      if (raw == null) return;
      _focusedByDay = (jsonDecode(raw) as Map).map((k, v) => MapEntry(k as String, v as int));
      notifyListeners();
    } catch (e) {
      debugPrint('[focus] focus seconds failed to load: $e');
    }
  }

  Future<void> _persistFocusSeconds() async {
    try {
      // A month of history is plenty for any view we show.
      final cutoff = _dayKey(DateTime.now().subtract(const Duration(days: 31)));
      _focusedByDay.removeWhere((k, _) => k.compareTo(cutoff) < 0);
      final p = await SharedPreferences.getInstance();
      await p.setString(_kFocusSeconds, jsonEncode(_focusedByDay));
    } catch (e) {
      debugPrint('[focus] focus seconds failed to save: $e');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
        _countSecond();
        notifyListeners();
      } else {
        end();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _bdHeartbeat?.cancel();
    _focusSaveDebounce?.cancel();
    _persistFocusSeconds();
    super.dispose();
  }
}
