import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../core/services/puter_service.dart';

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
    // Off-screen 1×1 - present but never seen or touchable.
    return Positioned(
      left: -2,
      top: -2,
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
