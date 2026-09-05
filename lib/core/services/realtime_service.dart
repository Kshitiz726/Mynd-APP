import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import 'api_client.dart';
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

  /// The token the live socket authenticated with, so a socket belonging to a
  /// previous session can be told apart from a usable one.
  String? _socketToken;

  void connect() {
    final token = ApiConfig.instance.authToken;

    // A socket built for a different token is not a connection, it is a dead
    // one that happens to exist.
    //
    // This returned early whenever `_socket != null`, which quietly broke
    // everything realtime after any sign-in that was not the first. The socket
    // gets built at launch with whatever token is around (often none, or one
    // the server has since stopped accepting), and the connect() call right
    // after signing in then did nothing at all. The socket kept retrying with
    // the old credentials, `ensureConnected` timed out, and body doubling
    // matched two people who could never be told about each other, because
    // `bd_matched` is pushed down exactly this socket.
    if (_socket != null && _socketToken == token) return;
    if (_socket != null) {
      debugPrint('[rt] token changed, rebuilding the socket');
      dispose();
    }

    _socketToken = token;
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
      // The server refused the handshake, and retrying with the same token is
      // not going to change its mind. Access tokens last thirty minutes and the
      // handshake verifies one, so this is what an ordinary expiry looks like
      // down here: reconnection attempts forever, ensureConnected timing out,
      // and body doubling reporting "no connection to the focus server" to
      // somebody whose session is perfectly valid and whose network is fine.
      // Trying again by hand could not fix it either, because nothing on this
      // path ever asked for a new token.
      if (_looksUnauthorized(e)) unawaited(_reauth());
    });
    s.onError((e) => debugPrint('[rt] error: $e'));

    debugPrint('[rt] connecting to ${ApiConfig.instance.baseUrl} '
        '(token=${ApiConfig.instance.authToken != null ? 'set' : 'NULL'})');
    s.connect();
  }

  /// Socket.IO hands the error through as a string, a map or an exception
  /// depending on where it failed, so this reads the rendered form rather than
  /// trying to type-match all three.
  ///
  /// The string it is looking for is not a guess: the server's handshake
  /// middleware rejects with `new Error('unauthorized')`, verified against the
  /// live server. If that wording ever changes, the refresh below stops firing
  /// and an expired token goes back to looking like a dead network - so the
  /// test pins it.
  @visibleForTesting
  static bool looksUnauthorized(Object? e) => _looksUnauthorized(e);

  static bool _looksUnauthorized(Object? e) {
    final t = '$e'.toLowerCase();
    return t.contains('unauthorized') || t.contains('401');
  }

  /// One refresh, however many connect_error callbacks arrive.
  ///
  /// Reconnection attempts are frequent, and each failed one fires this. Without
  /// the guard a dead token would launch a refresh per attempt, and because
  /// refreshing rotates the token, the losers of that race would install one the
  /// server had already replaced - turning a recoverable expiry into a session
  /// that genuinely cannot be repaired.
  bool _reauthing = false;

  Future<void> _reauth() async {
    if (_reauthing) return;
    _reauthing = true;
    try {
      if (!await ApiClient.instance.refreshSession()) return;
      // connect() rebuilds whenever the live socket's token is not the current
      // one, which it now is not. Scheduled rather than called inline: this runs
      // inside the socket's own error callback, and connect() disposes that
      // socket.
      await Future<void>.delayed(Duration.zero);
      connect();
    } finally {
      _reauthing = false;
    }
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
  ///
  /// Twenty five seconds rather than eight, because the server sleeps. Render's
  /// free tier spins the service down after fifteen minutes idle and takes tens
  /// of seconds to wake, so the first connection of a session routinely could
  /// not finish inside the old budget - and the caller reported a connection
  /// failure for a server that was merely still getting up. An expired token
  /// no longer costs the whole budget either: that path refreshes and rebuilds
  /// rather than retrying until the clock runs out.
  Future<bool> ensureConnected({
    Duration timeout = const Duration(seconds: 25),
  }) async {
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
    // Cleared with the socket, or the next connect() would compare against the
    // credentials of a socket that no longer exists and skip rebuilding.
    _socketToken = null;
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

  /// Change what the room is playing. Pass null to stop.
  ///
  /// [uri] must already be canonical - normaliseMusicUri is applied at the
  /// point the user pastes, so a rejection is shown against the text field
  /// rather than arriving later as a silent no-op. The server normalises again
  /// regardless; this is convenience, not the control.
  void setMusic(String roomId, String? uri, {String? title}) =>
      emit('set_music', {'roomId': roomId, 'uri': uri, 'title': title});

  /// Pause or resume the room's music for everyone. Separate from setMusic
  /// because the server rebuilds the shared playhead on resume, and that is
  /// arithmetic no client should be doing for the room.
  void setMusicPlayback(String roomId, bool paused) =>
      emit('set_music_playback', {'roomId': roomId, 'paused': paused});
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
