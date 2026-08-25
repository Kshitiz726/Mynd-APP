import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../core/constants/legal.dart';
import '../../core/services/api_client.dart';
import '../../core/services/google_auth.dart';
// Desktop-only real Google OAuth (loopback). Web/mobile pull in the stub.
import '../../core/services/desktop_google_auth_stub.dart'
    if (dart.library.io) '../../core/services/desktop_google_auth_io.dart'
    as desktop_auth;
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../widgets/fluid_orb.dart';
import '../../widgets/om_tappable.dart';
import '../onboarding/onboarding_gate.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;
  bool _showAuth = false;
  late final AnimationController _intro;

  /// Recognisers are long-lived objects that have to be disposed, so they are
  /// built once here rather than inline in build().
  late final TapGestureRecognizer _terms = TapGestureRecognizer()
    ..onTap = () => Legal.openTerms(context);
  late final TapGestureRecognizer _privacy = TapGestureRecognizer()
    ..onTap = () => Legal.openPrivacy(context);

  static const _desktopClientId =
      String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');

  bool get _googleNativeSupported => GoogleAuth.supported;

  @override
  void initState() {
    super.initState();
    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..forward();

    // Reveal the auth options once the logo has settled.
    //
    // This used to wait 2.5s, because this screen was doing double duty as the
    // splash. It is not any more - SplashScreen has already held the logo for
    // its own beat before this is even built - so the old delay stacked into
    // nearly five seconds of staring at a logo before you could press
    // anything. Just long enough now for the intro to land.
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _showAuth = true);
    });

    // Deliberately no silent auto-resume here.
    //
    // This screen used to call signInSilently() on build and, if the device had
    // ever granted us a Google account, sign straight in and navigate away -
    // without showing the login screen's buttons at all. On a fresh install
    // that reads as "the app decided who I am": a second person on the same
    // phone never saw "Continue with Google", they just landed inside somebody
    // else's account. Reaching this screen means we have no session, and the
    // right response to that is to ask, not to guess.
    //
    // A saved session still skips this screen entirely (see SessionStore in
    // main()), so the common case is unchanged.
  }

  @override
  void dispose() {
    _intro.dispose();
    _terms.dispose();
    _privacy.dispose();
    super.dispose();
  }

  Future<void> _handleTestSignIn() async {
    setState(() => _loading = true);
    Haptics.medium();
    try {
      final n = math.Random().nextInt(9000) + 1000;
      await ApiClient.instance
          .authWithGoogle(handle: 'test_$n', displayName: 'Test User $n');
      RealtimeService.instance.connect();
      if (mounted) OnboardingGate.enter(context);
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Test login failed: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Apple only implements this on its own platforms. Elsewhere the button is
  /// not shown at all, so nobody is offered a sign-in that cannot happen.
  bool get _appleSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _handleAppleSignIn() async {
    setState(() => _loading = true);
    Haptics.medium();

    try {
      debugPrint('[apple] 1/3 requesting credential…');
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      // Apple returns the name only on the very first authorisation, and never
      // again. We deliberately do not keep it: profiles here are anonymous, and
      // the server derives a stable display name of its own.
      final identityToken = credential.identityToken;
      debugPrint(
          '[apple] 2/3 credential ok, identityToken: ${identityToken == null ? "NULL" : "present"}');
      if (identityToken == null) {
        throw 'Apple returned no identity token. Check that the Sign in with '
            'Apple capability is enabled on the com.ourmynd.app App ID.';
      }

      debugPrint('[apple] 3/3 POST /api/auth/apple…');
      await ApiClient.instance.authWithAppleIdentityToken(identityToken);
      debugPrint('[apple] 3/3 backend accepted the token');

      RealtimeService.instance.connect();

      if (mounted) {
        OnboardingGate.enter(context);
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      // Backing out of the sheet is a choice, not a failure worth reporting.
      if (e.code != AuthorizationErrorCode.canceled && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Apple sign-in failed: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _loading = true);
    Haptics.medium();

    try {
      if (_googleNativeSupported) {
        // Always ask which account. Trying silently first meant the first
        // Google account to authorise this app became the only one it would
        // ever use - handing the phone to someone else signed them in as you,
        // and there was no way to switch. Pressing a button labelled "continue
        // with Google" should let you say which Google.
        //
        // Stage logging: this flow crosses Flutter -> GIDSignIn -> a web sheet
        // -> back, and when it stalls the screen just sits at "loading" with no
        // indication of which leg never returned. Each step announces itself so
        // a hang names its own stage in the log.
        debugPrint('[gsi] 1/4 chooseAccount — presenting sheet…');
        final account = await GoogleAuth.chooseAccount();
        debugPrint('[gsi] 2/4 returned: ${account?.email ?? "cancelled"}');
        if (account == null) return; // they backed out of the chooser

        debugPrint('[gsi] 3/4 fetching authentication/idToken…');
        final auth = await account.authentication;
        final idToken = auth.idToken;
        debugPrint('[gsi] 3/4 idToken: ${idToken == null ? "NULL" : "ok"}');
        if (idToken == null) {
          // Google hands back an ID token only when it knows who is asking.
          // Nine times out of ten the answer is that this particular build was
          // compiled without the client id - it is a --dart-define, so a plain
          // `flutter run` or `flutter build apk` silently produces an app that
          // can sign in with Google and never get a token. Say which of the two
          // it is rather than sending them to the Cloud console for a problem
          // that is in the build command.
          throw kIsWeb
              ? 'No ID token from Google. Check the Web Client ID in web/index.html '
                  'and that your origin is an authorised JavaScript origin.'
              : GoogleAuth.serverClientId.isEmpty
                  ? 'This build has no Google client id compiled in. Run it with '
                      '--dart-define=GOOGLE_SERVER_CLIENT_ID=… (see '
                      'run-android.local.sh) rather than a bare flutter run.'
                  : 'Google returned no ID token even though a client id is set. '
                      'Check that an Android OAuth client exists for this package '
                      'name and signing SHA-1.';
        }
        debugPrint('[gsi] 4/4 POST /api/auth/google…');
        await ApiClient.instance.authWithGoogleIdToken(idToken);
        debugPrint('[gsi] 4/4 backend accepted the token');
      } else if (_desktopClientId.isNotEmpty) {
        await desktop_auth.runDesktopGoogleAuth(clientId: _desktopClientId);
      } else {
        await _handleTestSignIn();
        return;
      }

      RealtimeService.instance.connect();

      if (mounted) {
        OnboardingGate.enter(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Login failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // ── Ambient mood lighting ──────────────────────────────────────────
          _Glow(
              color: c.primary,
              alignment: const Alignment(-0.9, -0.85),
              size: 360),
          _Glow(
              color: c.accent,
              alignment: const Alignment(1.1, 0.75),
              size: 420),
          _Glow(
              color: c.flow, alignment: const Alignment(0.9, -1.0), size: 280),

          // Splash Logo
          AnimatedAlign(
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeInOutCubic,
            alignment: _showAuth ? const Alignment(0, -0.6) : Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _intro,
                    curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
                  ),
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                        parent: _intro, curve: const Interval(0.0, 0.35)),
                    // The same living orb the splash, home and coach use, so the
                    // first face you meet is the one you keep. Gently alive here
                    // rather than held still - this is a welcome, not a resting
                    // home screen.
                    child: const FluidOrb(size: 132),
                  ),
                ),
              ],
            ),
          ),

          // Auth Section
          AnimatedOpacity(
            duration: const Duration(milliseconds: 800),
            opacity: _showAuth ? 1.0 : 0.0,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Log in or sign up',
                      textAlign: TextAlign.center,
                      style: t.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800, fontSize: 26),
                    ),
                    const SizedBox(height: 36),
                    _GoogleButton(
                        loading: _loading,
                        onTap: _showAuth ? _handleGoogleSignIn : null),
                    // Apple only offers this on Apple platforms, so on Android
                    // and desktop the button (and its spacer) go away rather
                    // than sitting there dead.
                    if (_appleSupported) ...[
                      const SizedBox(height: 12),
                      _AppleButton(
                          loading: _loading,
                          onTap: _showAuth ? _handleAppleSignIn : null),
                    ],
                    const SizedBox(height: 48),
                    // The acceptance line was a sentence *about* two documents
                    // with no way to reach either of them, on the one screen
                    // where agreeing to them is the thing being asked. Both
                    // halves are now the links they always claimed to be.
                    Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(
                              text: 'By continuing you agree to our '),
                          TextSpan(
                            text: 'Terms',
                            style: TextStyle(
                              color: c.primary,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                              decorationColor:
                                  c.primary.withValues(alpha: 0.4),
                            ),
                            recognizer: _terms,
                          ),
                          const TextSpan(text: ' & '),
                          TextSpan(
                            text: 'Privacy Policy',
                            style: TextStyle(
                              color: c.primary,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                              decorationColor:
                                  c.primary.withValues(alpha: 0.4),
                            ),
                            recognizer: _privacy,
                          ),
                          const TextSpan(text: '.'),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: t.labelSmall?.copyWith(
                          color: c.text2,
                          letterSpacing: 0.1,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A soft radial glow blob used for the ambient background lighting.
class _Glow extends StatelessWidget {
  const _Glow(
      {required this.color, required this.alignment, required this.size});
  final Color color;
  final Alignment alignment;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: context.isDark ? 0.22 : 0.18),
                color.withValues(alpha: 0.0)
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.loading, required this.onTap});
  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      pressedScale: 0.97,
      child: Container(
        height: 58,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: context.isDark ? 0.3 : 0.05),
              blurRadius: 16,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                    strokeWidth: 2.4, color: c.primary),
              )
            else ...[
              const SizedBox(
                  width: 22,
                  height: 22,
                  child: CustomPaint(painter: _GoogleGPainter())),
              const SizedBox(width: 14),
              Text(
                'Continue with Google',
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700, fontSize: 16),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AppleButton extends StatelessWidget {
  final bool loading;
  final VoidCallback? onTap;

  const _AppleButton({required this.loading, this.onTap});

  @override
  Widget build(BuildContext context) {
    return OmTappable(
      onTap: loading ? null : onTap,
      pressedScale: 0.98,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.apple, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text(
              'Continue with Apple',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The four-colour Google "G", drawn from arcs + the blue crossbar.
class _GoogleGPainter extends CustomPainter {
  const _GoogleGPainter();

  static const _blue = Color(0xFF4285F4);
  static const _red = Color(0xFFEA4335);
  static const _yellow = Color(0xFFFBBC05);
  static const _green = Color(0xFF34A853);

  double _d(double deg) => deg * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final w = size.shortestSide * 0.22; // stroke width
    final radius = (size.shortestSide - w) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.butt;

    // Clockwise from just below 3 o'clock (a small gap at the crossbar exit):
    canvas.drawArc(
        rect, _d(8), _d(82), false, p..color = _green); // bottom-right
    canvas.drawArc(
        rect, _d(90), _d(90), false, p..color = _yellow); // bottom-left
    canvas.drawArc(rect, _d(180), _d(90), false, p..color = _red); // top-left
    canvas.drawArc(rect, _d(270), _d(82), false, p..color = _blue); // top-right

    // Blue crossbar from centre to the right edge.
    final bar = RRect.fromRectAndRadius(
      Rect.fromLTRB(center.dx - w * 0.1, center.dy - w / 2,
          center.dx + radius + w / 2, center.dy + w / 2),
      Radius.circular(w * 0.1),
    );
    canvas.drawRRect(bar, Paint()..color = _blue);
  }

  @override
  bool shouldRepaint(_GoogleGPainter old) => false;
}
