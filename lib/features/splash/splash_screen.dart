import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/routes/app_router.dart';
import '../../core/theme/app_colors.dart';

/// The way in.
///
/// What was here was the OS window background: a static image that sat there
/// through every launch and then cut to whatever screen was next. The logo is
/// an animated thing everywhere else in the app, so the one moment it was
/// guaranteed to be still was the moment it was introducing itself.
///
/// This shows the app icon instead: the same mark that sits on the home
/// screen, so the tap that started the app is visibly continued rather than
/// answered with something else. It is precached before the first frame that
/// needs it, so there is never a blank hole to cover.
///
/// It holds for a deliberate beat even when the app was ready immediately,
/// because a splash that flashes past reads as a stutter rather than an
/// entrance. And it leaves on a fade, never a cut.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next, required this.bootAt});

  /// Where we are actually going: the shell if there is a session, the login
  /// screen if there is not. Decided before the app was built; this screen only
  /// covers the gap.
  final String next;

  /// When `main()` began.
  ///
  /// The wait is measured from here rather than from this widget being built,
  /// so a slow start does not *add* to it. Restoring the session, loading coach
  /// memory and setting up notification channels all happen before runApp, and
  /// counting from the widget would have stacked the splash on top of that
  /// instead of overlapping it.
  final DateTime bootAt;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// How long the whole entrance lasts, measured from `main()`.
  ///
  /// Kept short: long enough to see the orb settle, not long enough to feel like
  /// a wait. Most of the boot work overlaps this, so the app is usually ready
  /// well before it ends.
  static const _total = Duration(milliseconds: 2000);

  /// Never less than this, however slow the boot was. Without a floor, a start
  /// that took nearly the whole budget would leave the orb on screen for a few
  /// frames, which reads as a glitch rather than an entrance.
  static const _floor = Duration(milliseconds: 900);
  static const _fadeOut = Duration(milliseconds: 420);

  /// Hero size for the mark. Matches what the orb occupied, so the entrance
  /// keeps the same weight on screen.
  static const double _logoSize = 200;

  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  bool _precached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Decode the icon before it is painted. The orb this replaced was a shader
    // and needed nothing; an image does, and a splash screen is the one place
    // where a single blank frame is most visible - it is the whole content.
    if (!_precached) {
      _precached = true;
      precacheImage(const AssetImage('assets/logo.png'), context);
    }
  }

  Future<void> _run() async {
    debugPrint('[splash] start, next=${widget.next} bootAt=${widget.bootAt}');

    // Whatever is left of the budget after boot. The icon is precached in
    // didChangeDependencies, so this is purely about how long the entrance
    // should last rather than about waiting for anything to be ready.
    final spent = DateTime.now().difference(widget.bootAt);
    final left = _total - spent;
    debugPrint('[splash] spent=${spent.inMilliseconds}ms '
        'waiting=${(left < _floor ? _floor : left).inMilliseconds}ms');
    await Future<void>.delayed(left < _floor ? _floor : left);
    if (!mounted) return;

    debugPrint('[splash] fading out');
    setState(() => _leaving = true);
    await Future<void>.delayed(_fadeOut);
    if (!mounted) return;
    debugPrint('[splash] handing over to ${widget.next}');
    // Built straight from the router rather than pushed by name.
    //
    // This used to be load-bearing: the shell was named '/', which is also
    // where WidgetsApp registers `home` - this screen - so pushing the shell by
    // name landed back here and looped forever. The shell now has a name of its
    // own (see AppRoutes.shell), so the name would resolve correctly today.
    // Kept because it is still the more direct thing to do, and because it does
    // not depend on the route table agreeing with us.
    Navigator.of(context).pushReplacement(
      AppRouter.onGenerateRoute(RouteSettings(name: widget.next)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Scaffold(
      backgroundColor: c.bg,
      // Expanded explicitly. MaterialApp's builder wraps every route in a bare
      // Stack, which hands its children *loose* constraints, so a screen whose
      // content does not expand on its own collapses to the size of its
      // largest child. Every other screen in the app hides this behind a
      // ListView; this one is a logo in the middle of nothing.
      body: SizedBox.expand(
        child: Stack(
          alignment: Alignment.center,
          children: [
          // The same ambient wash the rest of the app sits on, so the fade out
          // lands on a background that is already familiar rather than a cut
          // from a white card to a coloured page.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0, -0.35),
                  radius: 1.1,
                  colors: [
                    c.primaryTint.withValues(alpha: context.isDark ? 0.5 : 0.9),
                    c.bg,
                  ],
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            duration: _fadeOut,
            curve: Curves.easeOutCubic,
            opacity: _leaving ? 0 : 1,
            child: AnimatedScale(
              duration: _fadeOut,
              curve: Curves.easeInCubic,
              // Leaves *towards* the viewer, which reads as the app opening
              // rather than the logo being dismissed.
              scale: _leaving ? 1.08 : 1,
              // The app icon itself, at hero size.
              //
              // This was the shader orb, which is the right mark *inside* the
              // app but the wrong one here: the launch screen's job is to
              // continue the tap that started it, and what the user tapped was
              // the icon on their home screen. Showing something else at that
              // moment reads as a different app opening.
              //
              // The icon is a rounded square, so it is masked to match the
              // platform's own app-icon shape rather than sitting as a hard
              // square on the wash. Precached in didChangeDependencies, so it
              // is decoded before the first frame that needs it and there is
              // no blank beat where the mark should be.
              child: ClipRRect(
                borderRadius: BorderRadius.circular(_logoSize * 0.2237),
                child: Image.asset(
                  'assets/logo.png',
                  width: _logoSize,
                  height: _logoSize,
                  // The source is 1024px and this draws at 200; letting the
                  // engine decode straight to the size it will paint saves
                  // decoding a megapixel to throw most of it away.
                  cacheWidth: (_logoSize * MediaQuery.devicePixelRatioOf(context)).round(),
                  filterQuality: FilterQuality.medium,
                ),
              ),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
