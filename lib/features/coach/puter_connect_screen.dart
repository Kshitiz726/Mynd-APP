import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/puter_service.dart';
import '../../core/theme/app_colors.dart';

/// Visible one-time Puter sign-in. The web page renders a real "Sign in to
/// Puter" button - tapping it inside the WebView grants the user activation that
/// `puter.auth.signIn()`'s popup requires (JS-injected sign-in from the
/// off-screen bridge is silently popup-blocked).
///
/// The sign-in popup is shown **in place** (swapping this one route's body)
/// rather than as a second pushed route - stacking two native WebViews froze
/// input on Windows after teardown. On success the obtained token is handed to
/// the off-screen bridge via [PuterService.applyToken].
///
/// This screen was removed when the provider picker was added, and the sheet
/// called `PuterService.signIn()` on the off-screen bridge instead. That bridge
/// is a 1x1 IgnorePointer surface, so it was a suspended opener driving a popup
/// pushed as a second route: both of the things the comments above say not to
/// do. The symptom was a sign-in screen that opened blank and never finished.
/// The lesson is in the two paragraphs above, which is why they are kept.
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
    // So the button this app draws shows through the page that catches the tap.
    transparentBackground: true,
  );

  int? _popupWindowId; // when set, the body shows the popup webview in place
  bool _done = false;
  bool _serverReady = false;

  @override
  void initState() {
    super.initState();
    // Make sure the loopback asset server is up (and we know its port) before we
    // point the WebView at it - otherwise the first load is a connection-refused.
    PuterService.instance.ensureServer().then((_) {
      if (mounted) setState(() => _serverReady = true);
    });
  }

  Future<void> _finish(bool ok, String token) async {
    if (_done) return;
    _done = true;
    if (ok && token.isNotEmpty) await PuterService.instance.applyToken(token);
    PuterService.instance.refreshAuth();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(ok);
    }
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
                // What the user actually looks at. It sits underneath the page
                // that catches the tap, which is transparent, so this shows
                // through. Without it the screen is blank and the only way to
                // get anywhere is to tap nothing in particular.
                Positioned.fill(child: _buildFace(context)),

                // The connect page is the OPENER of Puter's sign-in popup. It must
                // stay fully ACTIVE the whole time - not disposed (popup would
                // auto-close) and not Offstage (popup renders blank because a
                // suspended opener can't drive it). So we keep it painted and just
                // lay the popup webview on top of it. It stays full-bleed rather
                // than being sized to the button: the popup only survives an
                // opener the compositor is really drawing, and full-bleed is the
                // shape that was proven to work.
                Positioned.fill(child: _buildConnect()),

                if (_popupWindowId != null)
                  Positioned.fill(child: Material(child: _buildPopup())),
              ],
            ),
    );
  }

  /// The visible half of the screen. Not interactive: every tap goes to the
  /// transparent page above it, because that is the only tap Puter's popup
  /// blocker will accept. The button is drawn, not real, and the copy says to
  /// tap it so a tap that lands slightly off still makes sense.
  Widget _buildFace(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    return ColoredBox(
      color: c.bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: c.primaryTint,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(LucideIcons.sparkles, size: 28, color: c.primary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Sign in to Puter', style: t.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Puter is what lets the coach use Claude or Gemini without you '
              'creating an API key. Sign in once and it stays connected.',
              textAlign: TextAlign.center,
              style: t.bodyMedium?.copyWith(color: c.text2, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            Container(
              height: 54,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: c.brandGradient,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: const Text(
                'Sign in with Puter',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Tap anywhere on this screen to continue.',
              textAlign: TextAlign.center,
              style: t.bodySmall?.copyWith(color: c.text2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnect() {
    return InAppWebView(
      key: const ValueKey('puter-connect'),
      webViewEnvironment: PuterService.instance.env,
      initialUrlRequest: URLRequest(
          url: WebUri(
              'http://localhost:${PuterService.instance.serverPort}/connect.html')),
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
      onConsoleMessage: (_, msg) =>
          debugPrint('[puter:connect] ${msg.message}'),
      onCreateWindow: (controller, action) async {
        debugPrint(
            '[puter] connect onCreateWindow (windowId=${action.windowId})');
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
