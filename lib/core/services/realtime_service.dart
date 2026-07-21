import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_config.dart';

/// Single Socket.IO connection shared by Community + Focus features.
///
/// Mirrors the server event dictionary in `server/src/realtime/socket.ts`.
/// Connect once after sign-in; providers subscribe to the events they need.
class RealtimeService {
  RealtimeService._();
  static final RealtimeService instance = RealtimeService._();

  io.Socket? _socket;
  // Waiters parked until the NEXT connect/reconnect event (rebuilt each time so
  // a transient drop never leaves a caller stuck on a stale completed future).
  final List<Completer<void>> _waiters = [];
  final List<VoidCallback> _onReconnect = [];

  bool get connected => _socket?.connected ?? false;

  void connect() {
    if (_socket != null) return;
    final s = io.io(
      ApiConfig.instance.baseUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          .setAuth({'token': ApiConfig.instance.authToken})
          .enableReconnection()
          .build(),
    );
    _socket = s;
    // Whatever subscribed while there was no socket to subscribe to.
    _attachPending();

    s.onConnect((_) {
      debugPrint('[rt] connected id=${s.id}');
      _flushWaiters();
    });
    s.onReconnect((_) {
      debugPrint('[rt] reconnected');
      _flushWaiters();
      for (final cb in _onReconnect) {
        cb();
      }
    });
    s.onDisconnect((r) => debugPrint('[rt] disconnect: $r'));
    s.onConnectError((e) {
      debugPrint('[rt] connect_error: $e');
      s.auth = {'token': ApiConfig.instance.authToken}; // re-auth on next attempt
    });
    s.onError((e) => debugPrint('[rt] error: $e'));

    debugPrint('[rt] connecting to ${ApiConfig.instance.baseUrl} '
        '(token=${ApiConfig.instance.authToken != null ? 'set' : 'NULL'})');
    s.connect();
  }

  void _flushWaiters() {
    for (final c in _waiters) {
      if (!c.isCompleted) c.complete();
    }
    _waiters.clear();
  }

  /// Resolves true once the socket is live. Bounded so a caller never hangs
  /// forever on a socket that can't connect - it returns the current state
  /// after [timeout] and lets the caller surface a failure instead.
  Future<bool> ensureConnected({Duration timeout = const Duration(seconds: 8)}) async {
    connect();
    if (connected) return true;
    final c = Completer<void>();
    _waiters.add(c);
    try {
      await c.future.timeout(timeout);
    } on TimeoutException {
      _waiters.remove(c);
      debugPrint('[rt] ensureConnected timed out (connected=$connected)');
    }
    return connected;
  }

  void addReconnectListener(VoidCallback cb) => _onReconnect.add(cb);
  void removeReconnectListener(VoidCallback cb) => _onReconnect.remove(cb);

  void dispose() {
    _socket?.dispose();
    _socket = null;
  }

  // ── Emit (client → server) ──
  void emit(String event, Map<String, dynamic> payload) => _socket?.emit(event, payload);

  /// Emit and await the server's ack. Never hangs: returns `{ok:false}` if the
  /// socket can't connect or the ack doesn't arrive within the timeout.
  Future<Map<String, dynamic>> emitAck(String event, Map<String, dynamic> payload) async {
    final ok = await ensureConnected();
    if (!ok || _socket == null) {
      debugPrint('[rt] emitAck "$event" skipped - not connected');
      return {'ok': false, 'error': 'not connected'};
    }
    final c = Completer<Map<String, dynamic>>();
    _socket!.emitWithAck(event, payload, ack: (data) {
      debugPrint('[rt] ack "$event": $data');
      if (c.isCompleted) return;
      // socket.io may hand the ack back as the value or as a single-element list.
      if (data is Map) {
        c.complete(data.cast<String, dynamic>());
      } else if (data is List && data.isNotEmpty && data.first is Map) {
        c.complete((data.first as Map).cast<String, dynamic>());
      } else {
        c.complete(<String, dynamic>{});
      }
    });
    return c.future.timeout(const Duration(seconds: 10), onTimeout: () {
      debugPrint('[rt] ack "$event" TIMED OUT');
      return {'ok': false, 'error': 'timeout'};
    });
  }

  void joinRoom(String roomId) => emit('join_room', {'roomId': roomId});
  void leaveRoom(String roomId) => emit('leave_room', {'roomId': roomId});
  void heartbeat(String roomId) => emit('heartbeat', {'roomId': roomId});

  void setSession(String roomId, {required String task, required String mode, required int durationSecs}) =>
      emit('set_session', {'roomId': roomId, 'task': task, 'mode': mode, 'durationSecs': durationSecs});
  void timerControl(String roomId, String action) =>
      emit('timer_control', {'roomId': roomId, 'action': action}); // pause|resume|end

  void toggleMute(String roomId, bool muted) => emit('toggle_mute', {'roomId': roomId, 'muted': muted});
  void pttState(String roomId, bool talking) => emit('ptt_state', {'roomId': roomId, 'talking': talking});
  void setState(String roomId, String state) => emit('set_state', {'roomId': roomId, 'state': state});
  void setAmbience(String roomId, String ambience) =>
      emit('set_ambience', {'roomId': roomId, 'ambience': ambience});
  void voiceJoin(String roomId) => emit('voice_join', {'roomId': roomId});

  void watchPost(String postId) => emit('watch_post', {'postId': postId});
  void unwatchPost(String postId) => emit('unwatch_post', {'postId': postId});
  void react(String postId, String kind) => emit('new_reaction', {'postId': postId, 'kind': kind});

  // ── Chat ──
  /// Join the conversation room. Awaits the server ack so the caller knows
  /// subscription succeeded (and whether membership was rejected).
  Future<Map<String, dynamic>> openConversation(String id) =>
      emitAck('open_conversation', {'conversationId': id});

  Future<Map<String, dynamic>> sendMessage(
    String conversationId,
    String tempId, {
    String body = '',
    String kind = 'text',
    String? mediaUrl,
    Map<String, dynamic>? mediaMeta,
    String? replyToId,
  }) async {
    await ensureConnected();
    final ack = await emitAck('send_message', {
      'conversationId': conversationId,
      'clientTempId': tempId,
      'body': body,
      'kind': kind,
      if (mediaUrl != null) 'mediaUrl': mediaUrl,
      if (mediaMeta != null) 'mediaMeta': mediaMeta,
      if (replyToId != null) 'replyToId': replyToId,
    });
    return ack;
  }

  void typing(String conversationId, bool isTyping) =>
      emit('typing', {'conversationId': conversationId, 'isTyping': isTyping});

  // ── Listen (server → client) ──

  /// Subscriptions made before the socket existed.
  ///
  /// `_socket?.on(...)` silently does nothing when the socket is null, and
  /// null is the normal state during the first frames after launch - which is
  /// exactly when the widget tree wires up its listeners. Anything that
  /// subscribed from an initState was therefore deaf for the rest of the
  /// session, with no error to explain it. Handlers are kept here and attached
  /// again whenever a socket appears.
  final _pending = <MapEntry<String, void Function(Map<String, dynamic>)>>[];

  void on(String event, void Function(Map<String, dynamic>) handler) {
    _pending.add(MapEntry(event, handler));
    _attach(event, handler);
  }

  void _attach(String event, void Function(Map<String, dynamic>) handler) {
    _socket?.on(event, (data) => handler((data as Map).cast<String, dynamic>()));
  }

  void _attachPending() {
    for (final e in _pending) {
      _attach(e.key, e.value);
    }
  }

  void off(String event) {
    _pending.removeWhere((e) => e.key == event);
    _socket?.off(event);
  }
}
