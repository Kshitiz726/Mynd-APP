import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/routes/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/fluid_orb.dart';

/// The way in.
///
/// What was here was the OS window background: a static image that sat there
/// through every launch and then cut to whatever screen was next. The logo is
/// an animated thing everywhere else in the app, so the one moment it was
/// guaranteed to be still was the moment it was introducing itself.
///
/// This shows the real thing instead - the same shader-drawn orb the rest of
/// the app uses, so the logo you are introduced to is the logo you then live
/// with. It paints on the first frame it is asked to, with nothing to preload
/// and no decoder to wake up, so there is never a blank hole to cover.
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
  /// Long enough to watch the orb actually move through a shape or two, which
  /// is the point of it being alive rather than a logo.
  static const _total = Duration(milliseconds: 5000);

  /// Never less than this, however slow the boot was. Without a floor, a start
  /// that took nearly the whole budget would leave the orb on screen for a few
  /// frames, which reads as a glitch rather than an entrance.
  static const _floor = Duration(milliseconds: 1400);
  static const _fadeOut = Duration(milliseconds: 520);

  bool _leaving = false;

  /// Reduce-motion gets the orb holding still, and the same beat. The point of
  /// the setting is that nothing moves, not that nothing happens.
  bool _moving = true;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    _moving = !context.read<SettingsProvider>().reduceMotion;

    // Whatever is left of the budget after boot. There is nothing to preload -
    // the orb is a shader, ready on the frame it is first painted, which is
    // the whole reason it replaced a video that had to be decoded first - so
    // this is purely about how long the entrance should last.
    final spent = DateTime.now().difference(widget.bootAt);
    final left = _total - spent;
    await Future<void>.delayed(left < _floor ? _floor : left);
    if (!mounted) return;

    setState(() => _leaving = true);
    await Future<void>.delayed(_fadeOut);
    if (!mounted) return;
    // Built straight from the router rather than pushed by name.
    //
    // Not a style choice: this screen is MaterialApp's `home`, and WidgetsApp
    // registers `home` in its route table under '/'. AppRoutes.shell *is* '/',
    // so pushReplacementNamed(shell) resolved back to this screen - which
    // started another timer and pushed '/' again, forever, spawning a video
    // decoder each time round. Handing the router the settings directly skips
    // the table and lands on the screen we actually meant.
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
              // The same orb the app uses everywhere else, at hero size. No
              // preload, no decoder, and no still-frame stand-in to cross-fade
              // from: it paints on the first frame it is asked to.
              child: FluidOrb(size: 200, playing: _moving),
            ),
          ),
        ],
        ),
      ),
    );
  }
}
