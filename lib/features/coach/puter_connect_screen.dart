import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/services/puter_service.dart';

/// Visible one-time Puter sign-in. The web page renders a real "Sign in to
/// Puter" button — tapping it inside the WebView grants the user activation that
/// `puter.auth.signIn()`'s popup requires (JS-injected sign-in from the
/// off-screen bridge is silently popup-blocked).
///
/// The sign-in popup is shown **in place** (swapping this one route's body)
/// rather than as a second pushed route — stacking two native WebViews froze
/// input on Windows after teardown. On success the obtained token is handed to
/// the off-screen bridge via [PuterService.applyToken].
class PuterConnectScreen extends StatefulWidget {
  const PuterConnectScreen({super.key});

  @override
  State<PuterConnectScreen> createState() => _PuterConnectScreenState();
}

class _PuterConnectScreenState extends State<PuterConnectScreen> {
  static final _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: true,
    mediaPlaybackRequiresUserGesture: false,
    iframeAllow: 'microphone; camera; autoplay',
  );

  int? _popupWindowId; // when set, the body shows the popup webview in place
  bool _done = false;
  bool _serverReady = false;

  @override
  void initState() {
    super.initState();
    // Make sure the loopback asset server is up (and we know its port) before we
    // point the WebView at it — otherwise the first load is a connection-refused.
    PuterService.instance.ensureServer().then((_) {
      if (mounted) setState(() => _serverReady = true);
    });
  }

  Future<void> _finish(bool ok, String token) async {
    if (_done) return;
    _done = true;
    if (ok && token.isNotEmpty) await PuterService.instance.applyToken(token);
    PuterService.instance.refreshAuth();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop(ok);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_popupWindowId == null ? 'Connect Puter' : 'Sign in'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // Close the popup back to the connect page; or leave the screen.
            if (_popupWindowId != null) {
              setState(() => _popupWindowId = null);
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      body: !_serverReady
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // The connect page is the OPENER of Puter's sign-in popup. It must
                // stay fully ACTIVE the whole time — not disposed (popup would
                // auto-close) and not Offstage (popup renders blank because a
                // suspended opener can't drive it). So we keep it painted and just
                // lay the popup webview on top of it.
                _buildConnect(),
                if (_popupWindowId != null)
                  Positioned.fill(child: Material(child: _buildPopup())),
              ],
            ),
    );
  }

  Widget _buildConnect() {
    return InAppWebView(
      key: const ValueKey('puter-connect'),
      webViewEnvironment: PuterService.instance.env,
      initialUrlRequest: URLRequest(
          url: WebUri('http://localhost:${PuterService.instance.serverPort}/connect.html')),
      initialSettings: _settings,
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'onConnected',
          callback: (args) {
            final d = args.first as Map;
            _finish(d['ok'] == true, (d['token'] ?? '') as String);
          },
        );
      },
      onPermissionRequest: (controller, request) async => PermissionResponse(
        resources: request.resources,
        action: PermissionResponseAction.GRANT,
      ),
      onConsoleMessage: (_, msg) => debugPrint('[puter:connect] ${msg.message}'),
      onCreateWindow: (controller, action) async {
        debugPrint('[puter] connect onCreateWindow (windowId=${action.windowId})');
        setState(() => _popupWindowId = action.windowId);
        return true;
      },
    );
  }

  Widget _buildPopup() {
    return InAppWebView(
      key: ValueKey('puter-popup-$_popupWindowId'),
      webViewEnvironment: PuterService.instance.env,
      windowId: _popupWindowId,
      initialSettings: _settings,
      onConsoleMessage: (_, msg) => debugPrint('[puter:popup] ${msg.message}'),
      // Puter closes its own window after sign-in → return to the connect page,
      // whose signIn() promise resolves and fires onConnected.
      onCloseWindow: (_) {
        if (mounted) setState(() => _popupWindowId = null);
      },
    );
  }
}
