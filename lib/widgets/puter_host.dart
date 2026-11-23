import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/services/puter_service.dart';
import '../core/utils/test_mode.dart';

/// Invisible, app-lifetime WebView that hosts Puter.js for [PuterService].
///
/// Mounted once (in `main.dart`'s MaterialApp builder) so the JS bridge stays
/// alive across all routes. Kept 1×1 and off-screen - it never shows UI except
/// the one-time Puter sign-in popup, which is presented full-screen via
/// [navigatorKey] when `puter.auth` opens a window.
class PuterHost extends StatefulWidget {
  const PuterHost({super.key, required this.navigatorKey});

  final GlobalKey<NavigatorState> navigatorKey;

  @override
  State<PuterHost> createState() => _PuterHostState();
}

class _PuterHostState extends State<PuterHost> {
  static final _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: true,
    // Let puter.ai.txt2speech() autoplay + getUserMedia() capture the mic.
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,
    iframeAllow: 'microphone; camera; autoplay',
    transparentBackground: true,
  );

  // The bridge is served over http://localhost - a SECURE CONTEXT, required for
  // navigator.mediaDevices.getUserMedia (mic). The server itself is owned by the
  // app-lifetime [PuterService] (on an ephemeral port) so it survives this
  // widget rebuilding/disposing and never collides across two app instances.
  bool _ready = false;

  // Shared WebView environment lives on PuterService so the Connect screen reuses
  // it (same session/storage → the Puter token is visible to the bridge).
  WebViewEnvironment? get _env => PuterService.instance.env;

  @override
  void initState() {
    super.initState();
    // Nothing to bridge to under `flutter test`: there is no webview platform,
    // and booting anyway stood up a real localhost asset server with a periodic
    // timer that outlived the test. Guarded here rather than only in build,
    // because initState is where the side effects are.
    if (kTestMode) return;
    _boot();
  }

  Future<void> _boot() async {
    await PuterService.instance.ensureEnv();
    await PuterService.instance.ensureServer();
    if (mounted) setState(() => _ready = true);
  }

  @override
  void dispose() {
    // The asset server is app-lifetime (owned by PuterService) - don't close it.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // There is no webview platform under `flutter test`, and building one
    // throws, which took the app's boot smoke test down with it. The bridge is
    // pure platform plumbing with nothing to assert about, so it sits this out
    // rather than every widget test having to stub a browser.
    if (kTestMode) return const SizedBox.shrink();

    // A 1×1 in the very top-left corner - present but effectively invisible
    // (the bridge page is an empty, transparent document). It is kept ON-screen
    // rather than pushed off at negative coordinates on purpose: Android
    // suspends the mic capture of a WebView it considers off-screen, which was
    // cutting voice recordings off after a few seconds. A composited 1px surface
    // keeps getUserMedia/MediaRecorder running for the whole dump.
    return Positioned(
      left: 0,
      top: 0,
      width: 1,
      height: 1,
      child: IgnorePointer(
        child: !_ready
            ? const SizedBox.shrink()
            : InAppWebView(
                webViewEnvironment: _env,
                initialUrlRequest:
                    URLRequest(url: WebUri('http://localhost:${PuterService.instance.serverPort}/bridge.html')),
                initialSettings: _settings,
                onWebViewCreated: PuterService.instance.attachController,
                onPermissionRequest: (controller, request) async => PermissionResponse(
                  resources: request.resources,
                  action: PermissionResponseAction.GRANT,
                ),
                onConsoleMessage: (_, msg) => debugPrint('[puter:js] ${msg.message}'),
                onCreateWindow: _openAuthPopup,
              ),
      ),
    );
  }

  /// Puter's first-time sign-in opens a window - present it full-screen so the
  /// user can authenticate once (token is cached by the WebView afterwards).
  /// Returns `true` SYNCHRONOUSLY so the native WebView doesn't stall waiting on
  /// the dialog lifecycle (awaiting the push froze the bridge on Windows).
  ///
  /// This should not fire during a normal sign-in, and if it does, the sign-in
  /// will not work. The opener here is the 1x1 IgnorePointer surface above: a
  /// suspended opener cannot drive a popup, so the pushed route paints blank and
  /// `puter.auth.signIn()` rejects. Sign-in belongs to PuterConnectScreen, whose
  /// opener is a visible, full-size WebView. Kept only as a fallback that fails
  /// visibly rather than silently.
  Future<bool> _openAuthPopup(
    InAppWebViewController controller,
    CreateWindowAction action,
  ) async {
    debugPrint('[puter] onCreateWindow → opening sign-in popup (windowId=${action.windowId})');
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return false;
    // Fire-and-forget: schedule the popup, return immediately.
    nav.push(MaterialPageRoute(
      builder: (ctx) => _AuthPopup(windowId: action.windowId, settings: _settings, env: _env),
      fullscreenDialog: true,
    ));
    return true;
  }
}

class _AuthPopup extends StatelessWidget {
  const _AuthPopup({required this.windowId, required this.settings, this.env});

  final int windowId;
  final InAppWebViewSettings settings;
  final WebViewEnvironment? env;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sign in to Puter'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: InAppWebView(
        webViewEnvironment: env,
        windowId: windowId,
        initialSettings: settings,
        onCloseWindow: (_) => Navigator.of(context).maybePop(),
        onConsoleMessage: (_, msg) => debugPrint('[puter:auth] ${msg.message}'),
      ),
    );
  }
}
