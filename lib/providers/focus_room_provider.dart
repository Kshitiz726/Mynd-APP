import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../core/services/api_client.dart';
import '../core/services/api_config.dart';
import '../core/services/realtime_service.dart';
import '../core/services/voice_service.dart';
import '../models/focus/focus_room.dart';
import '../models/focus/room_participant.dart';

/// Drives a live Focus Room: presence grid, the participant timers, ambience,
/// mic state and the LiveKit voice session. Listens to the socket events in
/// `server/src/realtime/socket.ts`.
///
/// Note: this is the *room* (shared/body-doubling) counterpart to the existing
/// solo [FocusProvider]. The local 1s countdown still runs client-side; the
/// server's `timer_tick` is a 10s drift-correction heartbeat.
class FocusRoomProvider extends ChangeNotifier {
  final _rt = RealtimeService.instance;
  final _sfx = AudioPlayer();

  void _playSfx(String asset) {
    // Fire-and-forget presence chime; ignore failures (e.g. headless/test).
    _sfx.play(AssetSource(asset)).catchError((_) {});
  }

  // ── Room list ──
  List<FocusRoom> rooms = [];
  int globalLive = 0; // "62 minds focusing right now"

  // ── Active room ──
  String? activeRoomId;
  String ambience = 'cafe';
  final Map<String, RoomParticipant> _participants = {};
  List<RoomParticipant> get participants => _participants.values.toList();
  int get participantCount => _participants.length;

  FocusRoom? get activeRoom {
    if (activeRoomId == null) return null;
    try {
      return rooms.firstWhere((r) => r.id == activeRoomId);
    } catch (_) {
      return null;
    }
  }

  int myElapsedSecs = 0;

  Timer? _heartbeat;
  Timer? _localTick;
  bool _wired = false;

  bool _lobbyBound = false;

  void setRooms(List<FocusRoom> r, int global) {
    rooms = r;
    globalLive = global;
    bindLobby();
    notifyListeners();
  }

  /// Subscribe to live room-list updates: new public rooms appear, ended rooms
  /// disappear, and counts/global update - all without a refresh (Discord-style
  /// channel list). Safe to call repeatedly.
  void bindLobby() {
    if (_lobbyBound) return;
    _lobbyBound = true;

    _rt.on('room_created', (d) {
      final room = FocusRoom.fromJson(d);
      if (rooms.any((r) => r.id == room.id)) return;
      rooms = [...rooms, room];
      notifyListeners();
    });

    _rt.on('room_removed', (d) {
      rooms = rooms.where((r) => r.id != d['roomId']).toList();
      notifyListeners();
    });

    _rt.on('room_live_update', (d) {
      final id = d['roomId'];
      final count = d['count'] as int? ?? 0;
      rooms = [for (final r in rooms) if (r.id == id) r.withCount(count) else r];
      notifyListeners();
    });

    _rt.on('global_focus_update', (d) {
      globalLive = d['count'] as int? ?? globalLive;
      notifyListeners();
    });
  }

  /// Optimistically add a room the local user just created.
  void addRoom(FocusRoom room) {
    if (!rooms.any((r) => r.id == room.id)) {
      rooms = [...rooms, room];
      notifyListeners();
    }
  }

  // ── Join / leave ──
  void joinRoom(String roomId) {
    _wireListeners();
    activeRoomId = roomId;
    myElapsedSecs = 0;
    _rt.joinRoom(roomId);
    _rt.toggleMute(roomId, true); // Explicitly muted by default
    _rt.voiceJoin(roomId); // request a LiveKit token for body-doubling audio
    _heartbeat = Timer.periodic(const Duration(seconds: 25), (_) => _rt.heartbeat(roomId));
    _startLocalTick();
    notifyListeners();
  }

  Future<void> leaveRoom() async {
    final id = activeRoomId;
    final secs = myElapsedSecs;
    activeRoomId = null;
    _participants.clear();
    myElapsedSecs = 0;
    notifyListeners();

    if (id != null) {
      _rt.leaveRoom(id);
      try {
        await ApiClient.instance.completeSession(id, secs);
      } catch (e) {
        debugPrint('Failed to save session: $e');
      }
    }
    _heartbeat?.cancel();
    _localTick?.cancel();
    try {
      await VoiceService.instance.disconnect();
    } catch (_) {}
  }

  // ── Session / timer ──
  void setSession({required String task, required String mode, required int durationSecs}) {
    final id = activeRoomId;
    if (id != null) _rt.setSession(id, task: task, mode: mode, durationSecs: durationSecs);
  }

  void timerControl(String action) {
    final id = activeRoomId;
    if (id != null) _rt.timerControl(id, action);
  }

  // ── Mic / state / ambience ──
  void toggleMute(bool muted) {
    final id = activeRoomId;
    if (id == null) return;
    VoiceService.instance.setMuted(muted);
    _rt.toggleMute(id, muted);
  }

  void setTalking(bool talking) {
    final id = activeRoomId;
    if (id == null) return;
    VoiceService.instance.setTalking(talking);
    _rt.pttState(id, talking);
  }

  void raiseHand() {
    final id = activeRoomId;
    if (id != null) _rt.setState(id, 'need_help');
  }

  void setAmbience(String a) {
    final id = activeRoomId;
    if (id == null) return;
    ambience = a;
    _rt.setAmbience(id, a);
    notifyListeners();
  }

  // ── Socket wiring ──
  void _wireListeners() {
    if (_wired) return;
    _wired = true;

    _rt.on('room_state', (d) {
      ambience = d['ambience'] as String? ?? 'cafe';
      _participants
        ..clear()
        ..addEntries(((d['participants'] as List)
            .map((p) => RoomParticipant.fromJson((p as Map).cast()))
            .map((p) => MapEntry(p.userId, p))));
      notifyListeners();
    });

    _rt.on('participant_joined', (d) {
      final p = RoomParticipant.fromJson((d['participant'] as Map).cast());
      _participants[p.userId] = p;
      if (p.userId != myUserId) _playSfx('audio/join.wav');
      notifyListeners();
    });

    _rt.on('participant_left', (d) {
      final uid = d['userId'] as String?;
      _participants.remove(uid);
      if (uid != null && uid != myUserId) _playSfx('audio/leave.wav');
      notifyListeners();
    });

    _rt.on('participant_update', (d) {
      _participants[d['userId']]?.applyPatch((d['patch'] as Map).cast());
      notifyListeners();
    });

    _rt.on('room_count_update', (d) {
      // keep the room list card count fresh while inside the room
      final idx = rooms.indexWhere((r) => r.id == d['roomId']);
      if (idx >= 0) globalLive = globalLive; // counts surface via list refresh
      notifyListeners();
    });

    // Authoritative drift correction every ~10s (and on pause/resume/end).
    _rt.on('timer_tick', (d) {
      final p = _participants[d['userId']];
      if (p != null) {
        p.secondsRemaining = d['secondsRemaining'] as int?;
        p.timerRunning = d['running'] as bool? ?? false;
        notifyListeners();
      }
    });

    _rt.on('ambience_changed', (d) {
      ambience = d['ambience'] as String? ?? ambience;
      notifyListeners();
    });

    // Voice handshake: server replies to voice_join with a LiveKit token.
    _rt.on('voice_token', (d) {
      VoiceService.instance.connect(
        url: d['livekitUrl'] as String,
        token: d['token'] as String,
      );
    });
  }

  /// Local 1-second countdown for every running participant timer, so the grid
  /// ticks smoothly between server heartbeats.
  void _startLocalTick() {
    _localTick?.cancel();
    _localTick = Timer.periodic(const Duration(seconds: 1), (_) {
      myElapsedSecs++;
      var changed = true; // Always notify to update stopwatch
      for (final p in _participants.values) {
        if (p.timerRunning && (p.secondsRemaining ?? 0) > 0) {
          p.secondsRemaining = p.secondsRemaining! - 1;
          changed = true;
        }
      }
      if (changed) notifyListeners();
    });
  }

  String? get myUserId => ApiConfig.instance.userId;

  @override
  void dispose() {
    _heartbeat?.cancel();
    _localTick?.cancel();
    _sfx.dispose();
    super.dispose();
  }
}
