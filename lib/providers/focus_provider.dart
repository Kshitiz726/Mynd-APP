import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/api_client.dart';
import '../core/services/realtime_service.dart';
import '../models/focus_mode.dart';
import '../models/saved_focus.dart';

class FocusProvider extends ChangeNotifier {
  FocusProvider() {
    _loadSaved();
    _loadFocusSeconds();
  }

  FocusMode? _activeMode;
  String? _activeTaskTitle;
  int _secondsRemaining = 0;
  int _totalSeconds = 0;
  bool _isRunning = false;
  bool _bodyDoubling = false;
  Timer? _timer;

  // ── Body-doubling matchmaking (runs silently in the background) ──
  final _rt = RealtimeService.instance;
  bool _bdActive = false; // we're looking for / matched with a partner
  bool _searchingPartner = false; // still in the queue, no match yet
  String? _partnerName; // set once paired
  String? _bdRoomId; // the shared room both partners sit in
  Timer? _bdHeartbeat;
  bool _bdWired = false;

  FocusMode? get activeMode => _activeMode;

  /// What this session is *for*, when it was started from a schedule block or a
  /// saved focus. Null for a plain "just start a timer" session.
  String? get activeTaskTitle => _activeTaskTitle;
  int get secondsRemaining => _secondsRemaining;

  /// How long this session started out as, so progress rings stay honest when
  /// the length came from a task rather than the mode.
  int get totalSeconds => _totalSeconds == 0 ? 1 : _totalSeconds;
  bool get isRunning => _isRunning;
  bool get bodyDoubling => _bodyDoubling;
  bool get isActive => _activeMode != null;

  /// True while we're quietly waiting for a body-doubling partner.
  bool get searchingPartner => _searchingPartner;

  /// The matched partner's name, or null if none yet.
  String? get partnerName => _partnerName;

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
  }) {
    _activeMode = mode;
    _activeTaskTitle = taskTitle;
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
    _partnerName = null;
    _bdRoomId = null;
    _wireBd();
    notifyListeners();
    
    if (preMatchedRoomId != null) {
      _onMatched(preMatchedPartnerName, preMatchedRoomId);
      return;
    }

    try {
      final m = await ApiClient.instance.bodyDoublingMatch();
      if (!_bdActive) return; // session ended while we were requesting
      if (m.matched && m.roomId != null) {
        _onMatched(m.partner?.name, m.roomId!);
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
      _onMatched(partner?['displayName'] as String?, d['roomId'] as String?);
    });
  }

  void _onMatched(String? name, String? roomId) {
    if (roomId == null || _bdRoomId != null) return;
    _bdRoomId = roomId;
    _partnerName = name ?? 'a focus partner';
    _searchingPartner = false;
    // Sit both partners in the same room and share the pomodoro so each side
    // sees the other working alongside. The room auto-closes when both leave.
    _rt.joinRoom(roomId);
    final mode = _activeMode;
    if (mode != null) {
      _rt.setSession(roomId, task: 'Focus', mode: mode.name.toLowerCase(), durationSecs: _secondsRemaining);
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
    _partnerName = null;
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
