import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/puter_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../widgets/fluid_orb.dart';

/// What you see instead of the chat when Puter is not connected yet.
///
/// The coach runs on Puter, and Puter is user-pays, so there is a one-time
/// sign-in before any of this works. That used to be a small chip in the corner
/// of a chat that could not answer you: you could type, wait, and get a timeout
/// with no idea why. Better to say the one true thing up front and give it the
/// whole screen.
///
/// This screen *is* the connect step now. There used to be a second one - a web
/// page reading "Connect Puter / Sign in to Puter" - between this button and
/// Puter's actual sign-in, which asked you to agree to the same thing twice in
/// two different visual languages. It existed for a technical reason, not a
/// design one: `puter.auth.signIn()` opens a popup, and a popup is blocked
/// unless a real tap inside the WebView granted user activation first, so the
/// tap had to happen in web content.
///
/// It still does. That web content is now an invisible sheet laid exactly over
/// the button below (see `assets/puter/connect.html`): the app draws the
/// button, the page catches the tap. One screen, then Puter.
class PuterGate extends StatefulWidget {
  const PuterGate({super.key});

  @override
  State<PuterGate> createState() => _PuterGateState();
}

class _PuterGateState extends State<PuterGate> {
  static final _settings = InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    supportMultipleWindows: true,
    transparentBackground: true,
    mediaPlaybackRequiresUserGesture: false,
    iframeAllow: 'microphone; camera; autoplay',
  );

  /// The loopback asset server has to be up, and its port known, before the
  /// WebView is pointed at it, or the first load is a connection-refused.
  bool _serverReady = false;

  /// True from the tap until Puter's window is on screen. That wait is a second
  /// or two of network, and an unexplained one on a button that has visibly
  /// done nothing reads as a dead button.
  bool _opening = false;

  bool _done = false;
  OverlayEntry? _popup;

  @override
  void initState() {
    super.initState();
    PuterService.instance.ensureServer().then((_) {
      if (mounted) setState(() => _serverReady = true);
    });
  }

  @override
  void dispose() {
    _closePopup();
    super.dispose();
  }

  Future<void> _finish(bool ok, String token) async {
    if (_done) return;
    _done = true;
    _closePopup();
    if (ok && token.isNotEmpty) await PuterService.instance.applyToken(token);
    PuterService.instance.refreshAuth();
    if (mounted) setState(() => _opening = false);
  }

  void _closePopup() {
    _popup?.remove();
    _popup = null;
  }

  /// Puter's own sign-in, full screen.
  ///
  /// It goes in the overlay rather than on a pushed route for two reasons: the
  /// page that opened it has to stay alive and painted the whole time (a
  /// disposed opener closes the popup, a suspended one renders it blank), and
  /// two native WebViews on two routes froze input on Windows after teardown.
  void _openPopup(int windowId) {
    _closePopup();
    final overlay = Overlay.of(context, rootOverlay: true);
    _popup = OverlayEntry(
      builder: (_) => Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _closePopup();
                    if (mounted) setState(() => _opening = false);
                  },
                ),
              ),
              Expanded(
                child: InAppWebView(
                  key: ValueKey('puter-popup-$windowId'),
                  webViewEnvironment: PuterService.instance.env,
                  windowId: windowId,
                  initialSettings: _settings,
                  onConsoleMessage: (_, msg) =>
                      debugPrint('[puter:popup] ${msg.message}'),
                  // Puter closes its own window after sign-in → the connect
                  // sheet's signIn() promise resolves and fires onConnected.
                  onCloseWindow: (_) {
                    _closePopup();
                    if (mounted) setState(() => _opening = false);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    overlay.insert(_popup!);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FluidOrb(size: 132),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'MYND',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      color: c.primary,
                    ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your coach runs on Puter, so it needs a Puter account before '
                'it can talk to you.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: c.text2, height: 1.55),
              ),
              const SizedBox(height: 8),
              Text(
                'You only do this once.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _button(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _button(OmColors c) {
    return SizedBox(
      height: 54,
      width: double.infinity,
      child: Stack(
        children: [
          // The button, drawn by us. It carries no onTap and needs none: the
          // invisible sheet above it is what the finger actually lands on.
          Positioned.fill(
            child: AnimatedOpacity(
              opacity: _serverReady ? 1 : 0.55,
              duration: const Duration(milliseconds: 220),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: c.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color: c.primary.withValues(alpha: 0.34),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: _opening
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2.2, color: Colors.white),
                        )
                      : const Text(
                          'Sign in with Puter',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          ),
          // Mounted from the moment the server is up and never taken down,
          // including while signing in. It is the window that OPENED Puter's
          // popup, and a popup whose opener has been disposed cannot report
          // back: Puter calls `window.opener.postMessage` when the sign-in
          // succeeds, and gets null. Hiding this to show a spinner cost
          // exactly that, and the failure looked like a hang on Puter's side.
          if (_serverReady)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.pill),
                child: _tapSheet(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _tapSheet() {
    return InAppWebView(
      key: const ValueKey('puter-connect'),
      webViewEnvironment: PuterService.instance.env,
      initialUrlRequest: URLRequest(
          url: WebUri(
              'http://localhost:${PuterService.instance.serverPort}/connect.html')),
      initialSettings: _settings,
      onWebViewCreated: (controller) {
        controller
          ..addJavaScriptHandler(
            handlerName: 'onReady',
            callback: (_) => null,
          )
          ..addJavaScriptHandler(
            handlerName: 'onOpening',
            callback: (_) {
              Haptics.medium();
              if (mounted) setState(() => _opening = true);
              return null;
            },
          )
          ..addJavaScriptHandler(
            handlerName: 'onConnected',
            callback: (args) {
              final d = args.first as Map;
              _finish(d['ok'] == true, (d['token'] ?? '') as String);
              return null;
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
        debugPrint('[puter] connect onCreateWindow (${action.windowId})');
        _openPopup(action.windowId);
        return true;
      },
    );
  }
}
