import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default Puter chat model. Puter exposes 400+ models; swap freely.
///
/// Was `gpt-5.4-nano`, which is where a lot of the coach's "dumbness" actually
/// came from: nano is a speed tier, and it shows the moment a reply needs to
/// hold their context and a real answer at the same time. The full model is a
/// little slower to first token and worth it, since every reply streams.
const String kPuterChatModel = 'openai/gpt-5.5';

/// The model picker shown in the coach (mirrors index.html's catalog).
const List<({String id, String label})> kPuterModels = [
  (id: 'openai/gpt-5.5', label: 'GPT-5.5 (OpenAI)'),
  (id: 'gpt-5.4-nano', label: 'GPT-5.4 Nano (fast)'),
  (id: 'gpt-5.4', label: 'GPT-5.4'),
  (id: 'anthropic/claude-opus-4-8', label: 'Claude Opus 4.8'),
  (id: 'google/gemini-3.5-flash', label: 'Gemini 3.5 Flash'),
  (id: 'x-ai/grok-4.3', label: 'Grok 4.3 (xAI)'),
  (id: 'deepseek/deepseek-v4-pro', label: 'DeepSeek V4 Pro'),
  (id: 'meta-llama/llama-4-maverick', label: 'Llama 4 Maverick'),
];

/// Voice-session lifecycle, surfaced to the talk UI for its orb animation.
enum PuterVoiceState { idle, listening, transcribing, thinking, speaking }

/// Bridges the native app to **Puter.js** (a browser-only library) by hosting
/// it inside an embedded WebView and shuttling calls across a JS bridge.
///
/// The [PuterHost] widget owns the actual `InAppWebView`; it hands us the
/// controller via [attachController] and signals JS readiness. Everything the
/// coach needs - streaming chat, blocking completion, speech-to-text and
/// text-to-speech - runs through `puter.ai.*` inside that page.
class PuterService {
  PuterService._();
  static final PuterService instance = PuterService._();

  InAppWebViewController? _controller;
  final Completer<void> _ready = Completer<void>();
  Future<void> get ready => _ready.future;
  bool get isReady => _ready.isCompleted;

  int _seq = 0;
  final Map<int, StreamController<String>> _chatStreams = {};
  final Map<int, Completer<String>> _completes = {};
  final Map<int, Timer> _watchdogs = {};

  /// Currently-selected chat model (the coach model picker writes this).
  String model = kPuterChatModel;
  void setModel(String id) => model = id;

  // Auth (Puter user-pays needs a one-time sign-in popup)
  bool signedIn = false;
  final _authState = StreamController<bool>.broadcast();
  Stream<bool> get authState => _authState.stream;

  // Shared WebView environment (Windows/WebView2) so the off-screen bridge and
  // the visible Connect screen share session + storage (the Puter token).
  WebViewEnvironment? env;
  Future<void> ensureEnv() async {
    if (env != null || !Platform.isWindows) return;
    try {
      env = await WebViewEnvironment.create();
    } catch (e) {
      debugPrint('[puter] WebViewEnvironment.create failed: $e');
    }
  }

  // ── Local bridge server ──────────────────────────────────────────────────
  // The bridge/connect HTML is served over a real loopback HTTP server (a
  // SECURE CONTEXT, so getUserMedia/mic works). We use dart:io's HttpServer on
  // an EPHEMERAL port instead of a fixed-port InAppLocalhostServer because the
  // latter is unreliable on Windows AND a fixed port collides when two app
  // instances run - both were the "localhost refused to connect" on Connect.
  HttpServer? _assetServer;
  int? _serverPort;
  Completer<void>? _serverReady;

  /// The port the bridge HTML is served on (0 until [ensureServer] completes).
  int get serverPort => _serverPort ?? 0;

  /// Start the loopback asset server once. Safe to call repeatedly.
  Future<void> ensureServer() async {
    if (_serverReady != null) return _serverReady!.future;
    final ready = Completer<void>();
    _serverReady = ready;
    try {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _assetServer = server;
      _serverPort = server.port;
      server.listen((req) async {
        try {
          var path = req.uri.path;
          if (path == '/' || path.isEmpty) path = '/bridge.html';
          final data = await rootBundle.load('assets/puter$path');
          final bytes =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
          req.response
            ..statusCode = 200
            ..headers.contentType = _contentTypeFor(path)
            ..add(bytes);
          await req.response.close();
        } catch (_) {
          req.response.statusCode = 404;
          await req.response.close();
        }
      });
      debugPrint('[puter] asset server on http://localhost:$_serverPort');
    } catch (e) {
      debugPrint('[puter] asset server bind failed: $e');
    } finally {
      if (!ready.isCompleted) ready.complete();
    }
  }

  ContentType _contentTypeFor(String path) {
    if (path.endsWith('.html')) return ContentType.html;
    if (path.endsWith('.js'))
      return ContentType('application', 'javascript', charset: 'utf-8');
    if (path.endsWith('.css'))
      return ContentType('text', 'css', charset: 'utf-8');
    return ContentType.binary;
  }

  // Voice
  final _voiceState = StreamController<PuterVoiceState>.broadcast();
  Stream<PuterVoiceState> get voiceState => _voiceState.stream;
  PuterVoiceState _state = PuterVoiceState.idle;
  PuterVoiceState get state => _state;
  Completer<void>? _spoken;

  // Mic capture: the bridge records audio and hands the base64 clip back here;
  // Dart transcribes it with Groq Whisper. A live loudness stream drives the orb.
  Completer<String>? _audioCap;

  /// Resolves with null when the mic opened, or the browser's reason when it did
  /// not. Separate from [_audioCap] because a start failure arrives when no
  /// audio is pending.
  Completer<String?>? _recStart;
  final _levelCtrl = StreamController<double>.broadcast();
  Stream<double> get voiceLevel => _levelCtrl.stream;

  // ───────────────────────── Wiring (called by PuterHost) ─────────────────────

  void attachController(InAppWebViewController controller) {
    _controller = controller;
    controller
      ..addJavaScriptHandler(
          handlerName: 'onReady',
          callback: (args) {
            if (!_ready.isCompleted) _ready.complete();
            final d = args.isNotEmpty ? args.first as Map : const {};
            _setSignedIn(d['signedIn'] == true);
            debugPrint('[puter] bridge ready (signedIn=$signedIn)');
            // A fresh WebView starts signed out even for someone who connected
            // months ago, so hand it back the token we kept rather than sending
            // them through a sign-in they have already done.
            if (!signedIn) unawaited(restoreSavedSession());
          })
      ..addJavaScriptHandler(
          handlerName: 'onAuth',
          callback: (args) {
            final d = args.first as Map;
            _setSignedIn(d['signedIn'] == true);
            debugPrint('[puter] auth → signedIn=$signedIn ${d['error'] ?? ''}');
          })
      ..addJavaScriptHandler(
          handlerName: 'onLog',
          callback: (args) {
            debugPrint('[puter:log] ${args.first}');
          })
      ..addJavaScriptHandler(
          handlerName: 'onChunk',
          callback: (args) {
            final d = args.first as Map;
            final id = d['id'] as int;
            _watchdogs.remove(id)?.cancel(); // first token → no longer "stuck"
            _chatStreams[id]?.add((d['chunk'] ?? '') as String);
          })
      ..addJavaScriptHandler(
          handlerName: 'onDone',
          callback: (args) {
            final d = args.first as Map;
            final id = d['id'] as int;
            _watchdogs.remove(id)?.cancel();
            _completes.remove(id)?.complete((d['full'] ?? '') as String);
            final s = _chatStreams.remove(id);
            if (s != null && !s.isClosed) s.close();
          })
      ..addJavaScriptHandler(
          handlerName: 'onError',
          callback: (args) {
            final d = args.first as Map;
            final id = d['id'] as int? ?? -1;
            _watchdogs.remove(id)?.cancel();
            final err = PuterException((d['error'] ?? 'puter error') as String);
            debugPrint('[puter] error: ${err.message}');
            _completes.remove(id)?.completeError(err);
            final s = _chatStreams.remove(id);
            if (s != null && !s.isClosed) {
              s.addError(err);
              s.close();
            }
          })
      ..addJavaScriptHandler(
          handlerName: 'onVoiceState',
          callback: (args) {
            final st = ((args.first as Map)['state'] ?? 'idle') as String;
            _emitState(switch (st) {
              'listening' => PuterVoiceState.listening,
              'transcribing' => PuterVoiceState.transcribing,
              'speaking' => PuterVoiceState.speaking,
              _ => PuterVoiceState.idle,
            });
          })
      ..addJavaScriptHandler(
          handlerName: 'onAudio',
          callback: (args) {
            final d = args.first as Map;
            final err = d['error'];
            if (err != null) debugPrint('[voice] recorder error: $err');
            _audioCap?.complete((d['b64'] ?? '') as String);
            _audioCap = null;
          })
      ..addJavaScriptHandler(
          handlerName: 'onRecStarted',
          callback: (args) {
            final d = args.first as Map;
            final ok = d['ok'] == true;
            if (!ok) debugPrint('[voice] mic open failed: ${d['error']}');
            if (_recStart?.isCompleted == false) {
              _recStart!.complete(ok ? null : '${d['error']}');
            }
          })
      ..addJavaScriptHandler(
          handlerName: 'onVoiceLevel',
          callback: (args) {
            final lvl = ((args.first as Map)['level'] ?? 0) as num;
            if (!_levelCtrl.isClosed) _levelCtrl.add(lvl.toDouble());
          })
      ..addJavaScriptHandler(
          handlerName: 'onSpoken',
          callback: (_) {
            _emitState(PuterVoiceState.idle);
            _spoken?.complete();
            _spoken = null;
          });
  }

  void _emitState(PuterVoiceState s) {
    _state = s;
    if (!_voiceState.isClosed) _voiceState.add(s);
  }

  void _setSignedIn(bool v) {
    signedIn = v;
    if (!_authState.isClosed) _authState.add(v);
  }

  /// Trigger Puter's sign-in popup; resolves the auth state via [authState].
  Future<void> signIn() => _eval('window.omSignIn();');
  void refreshAuth() => _eval('window.omAuthCheck();');

  /// Hand the off-screen bridge the token obtained by the visible Connect screen
  /// (separate webview), so it becomes authenticated without its own popup.
  ///
  /// The token is also written to disk. Connecting Puter is a one-time job from
  /// the user's point of view, and it has to actually be one: the WebView's own
  /// storage is not a promise, it is a cache the OS is free to clear, and every
  /// time it did the user was asked to sign in to something they had already
  /// signed in to. Keeping our own copy makes the promise ours to keep.
  Future<void> applyToken(String token) async {
    if (token.isEmpty) {
      refreshAuth();
      return;
    }
    await _saveToken(token);
    await _eval("window.omApplyToken('${_encStr(token)}');");
  }

  static const _kToken = 'om_puter_token';

  Future<void> _saveToken(String token) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kToken, token);
    } catch (e) {
      debugPrint('[puter] token save failed: $e');
    }
  }

  /// Re-authenticate the bridge from the token we saved last time.
  ///
  /// Called when the bridge reports ready and says it is signed out. If we have
  /// a token, the user has connected before and should not be asked again; if
  /// the token has been revoked server-side the bridge will simply report
  /// signed-out once more and the gate appears, which is the correct outcome.
  Future<bool> restoreSavedSession() async {
    if (signedIn) return true;
    try {
      final p = await SharedPreferences.getInstance();
      final token = p.getString(_kToken);
      if (token == null || token.isEmpty) return false;
      await _eval("window.omApplyToken('${_encStr(token)}');");
      return true;
    } catch (e) {
      debugPrint('[puter] token restore failed: $e');
      return false;
    }
  }

  /// Forget the connection entirely. Only for sign-out.
  Future<void> clearSavedSession() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kToken);
    } catch (_) {}
    _setSignedIn(false);
  }

  /// Reload the bridge page (re-reads any shared-storage Puter token).
  void reloadBridge() => _controller?.reload();

  /// Reload the bridge and wait until it reports signed in.
  ///
  /// Used right after the visible Connect screen finishes Puter's sign-in: the
  /// bridge shares the connect page's localhost origin, so a reload re-reads the
  /// session Puter.js just wrote and comes back authenticated. Resolves when the
  /// bridge confirms it (or after a short timeout, so the caller never hangs).
  Future<void> reloadBridgeAndAwaitAuth() async {
    if (signedIn) return;
    final done = Completer<void>();
    final sub = authState.listen((v) {
      if (v && !done.isCompleted) done.complete();
    });
    _controller?.reload();
    try {
      await done.future.timeout(const Duration(seconds: 6));
    } catch (_) {
      // Not signed in after the reload - the gate correctly stays.
    } finally {
      await sub.cancel();
    }
  }

  Future<void> _eval(String js) async {
    await ready;
    await _controller?.evaluateJavascript(source: js);
  }

  String _enc(Object o) => base64.encode(utf8.encode(jsonEncode(o)));
  String _encStr(String s) => base64.encode(utf8.encode(s));

  // ───────────────────────── Chat API (mirrors GroqService) ────────────────────

  /// Streams the assistant reply token-by-token via `puter.ai.chat(stream:true)`.
  /// A watchdog guarantees the stream errors instead of hanging forever (e.g.
  /// when Puter isn't signed in) so the coach never sticks on "…".
  Stream<String> streamCompletion(List<Map<String, String>> messages,
      {String? model}) {
    final id = _seq++;
    final ctrl = StreamController<String>();
    _chatStreams[id] = ctrl;
    _watchdogs[id] = Timer(const Duration(seconds: 40), () {
      _watchdogs.remove(id);
      final s = _chatStreams.remove(id);
      if (s != null && !s.isClosed) {
        s.addError(PuterException(signedIn
            ? 'Puter timed out - try again'
            : 'Not connected to Puter - tap "Connect Puter"'));
        s.close();
      }
    });
    _eval("window.omChat($id, '${_enc(messages)}', '${model ?? this.model}');")
        .catchError((Object e) {
      _watchdogs.remove(id)?.cancel();
      if (!ctrl.isClosed) {
        ctrl.addError(e);
        ctrl.close();
      }
      _chatStreams.remove(id);
    });
    ctrl.onCancel = () {
      _watchdogs.remove(id)?.cancel();
      _chatStreams.remove(id);
    };
    return ctrl.stream;
  }

  /// Blocking completion - for memory summarisation.
  Future<String> complete(List<Map<String, String>> messages,
      {String? model}) async {
    final id = _seq++;
    final c = Completer<String>();
    _completes[id] = c;
    await _eval(
        "window.omComplete($id, '${_enc(messages)}', '${model ?? this.model}');");
    return c.future.timeout(const Duration(seconds: 45), onTimeout: () {
      _completes.remove(id);
      throw PuterException('completion timed out');
    });
  }

  // ───────────────────────────── Voice API ─────────────────────────────────────

  /// Start capturing the mic in the bridge WebView (a secure localhost context
  /// where getUserMedia works). Loudness arrives on [voiceLevel] meanwhile.
  ///
  /// Waits for the recorder to confirm the mic actually opened, and throws with
  /// the browser's reason if it did not. Firing the JS and returning was the
  /// bug behind "it never listens": `_eval` succeeds as long as the script runs,
  /// so a refused getUserMedia still looked like a successful start, and the
  /// only symptom was an empty transcript a minute later.
  Future<void> startCapture() async {
    _recStart = Completer<String?>();
    final fut = _recStart!.future;
    await _eval('window.omRecStart();');
    final err = await fut.timeout(
      const Duration(seconds: 10),
      onTimeout: () => 'the recorder did not respond',
    );
    _recStart = null;
    if (err != null) throw StateError(err);
  }

  /// Stop capturing and resolve with the recorded audio bytes (empty on
  /// failure). The caller sends these to Groq Whisper to get text.
  Future<List<int>> stopCapture() async {
    _audioCap = Completer<String>();
    final fut = _audioCap!.future;
    await _eval('window.omRecStop();');
    final b64 = await fut.timeout(const Duration(seconds: 20), onTimeout: () {
      _audioCap = null;
      return '';
    });
    if (b64.isEmpty) return const [];
    try {
      return base64.decode(b64);
    } catch (_) {
      return const [];
    }
  }

  /// Abandon the current capture without returning audio.
  void cancelCapture() {
    _audioCap = null;
    _eval('window.omRecCancel();');
  }

  /// Speaks [text] aloud; resolves when playback ends.
  Future<void> speak(String text) {
    _spoken = Completer<void>();
    _eval("window.omSpeak('${_encStr(text)}');");
    return _spoken!.future.timeout(const Duration(seconds: 90), onTimeout: () {
      _spoken = null;
      _emitState(PuterVoiceState.idle);
    });
  }

  void stopSpeaking() => _eval('window.omStopSpeak();');

  void resetVoice() => _emitState(PuterVoiceState.idle);
}

class PuterException implements Exception {
  PuterException(this.message);
  final String message;
  @override
  String toString() => 'PuterException: $message';
}
