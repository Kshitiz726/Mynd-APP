import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/services/api_client.dart';
import '../core/services/realtime_service.dart';
import '../models/focus_mode.dart';

class FocusProvider extends ChangeNotifier {
  FocusMode? _activeMode;
  int _secondsRemaining = 0;
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
  int get secondsRemaining => _secondsRemaining;
  bool get isRunning => _isRunning;
  bool get bodyDoubling => _bodyDoubling;
  bool get isActive => _activeMode != null;

  /// True while we're quietly waiting for a body-doubling partner.
  bool get searchingPartner => _searchingPartner;

  /// The matched partner's name, or null if none yet.
  String? get partnerName => _partnerName;

  String get timeString {
    final m = (_secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final s = (_secondsRemaining % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void start(FocusMode mode, bool bodyDoubling, {String? preMatchedRoomId, String? preMatchedPartnerName}) {
    _activeMode = mode;
    _secondsRemaining = mode.minutes * 60;
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

  void end() {
    _timer?.cancel();
    _endBodyDoubling();
    _activeMode = null;
    _isRunning = false;
    _secondsRemaining = 0;
    _bodyDoubling = false;
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
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
    super.dispose();
  }
}
