import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/routes/app_router.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/settings_provider.dart';

/// The way in.
///
/// What was here was the OS window background: a static image that sat there
/// through every launch and then cut to whatever screen was next. The logo is
/// an animated thing everywhere else in the app, so the one moment it was
/// guaranteed to be still was the moment it was introducing itself.
///
/// This plays the real thing instead, and the timing is the whole point:
///
///  - The still frame paints first, on the very first frame, so there is never
///    a blank hole while a decoder wakes up. It is frame 0 of the video (byte
///    for byte, not by eye), so when the video fades in on top there is
///    nothing to jump between.
///  - It holds for a deliberate beat even if the app was ready immediately,
///    because a splash that flashes past reads as a stutter rather than an
///    entrance.
///  - If the app is *not* ready it keeps playing rather than freezing on a
///    frame. The loop is seamless now, so waiting looks like breathing.
///  - It leaves on a fade, never a cut.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.next});

  /// Where we are actually going: the shell if there is a session, the login
  /// screen if there is not. Decided before the app was built; this screen only
  /// covers the gap.
  final String next;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  /// Long enough to register as a deliberate entrance, short enough that
  /// nobody waiting to use the app resents it.
  static const _minShow = Duration(milliseconds: 2200);
  static const _fadeOut = Duration(milliseconds: 520);

  VideoPlayerController? _video;
  bool _videoReady = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final started = DateTime.now();
    // Reduce-motion gets the still frame and the same beat. The point of the
    // setting is that nothing moves, not that nothing happens.
    final reduceMotion = context.read<SettingsProvider>().reduceMotion;

    if (!reduceMotion) {
      final c = VideoPlayerController.asset('assets/video/fluid.mp4');
      try {
        // Fully initialised before it is ever shown - the decoder buffering
        // mid-frame is what a "laggy" loop usually is.
        await c.initialize();
        await c.setLooping(true);
        await c.setVolume(0);
        await c.play();
        if (!mounted) {
          await c.dispose();
          return;
        }
        setState(() {
          _video = c;
          _videoReady = true;
        });
      } catch (_) {
        // The still frame is already on screen and is a perfectly good logo.
        await c.dispose();
      }
    }

    // Whatever is left of the beat after the decoder took its time.
    final elapsed = DateTime.now().difference(started);
    final remaining = _minShow - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
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
  void dispose() {
    _video?.dispose();
    super.dispose();
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
              child: SizedBox(
                width: 200,
                height: 200,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Frame 0, painted immediately. Never a blank hole.
                    Image.asset('assets/img/logo_static.png',
                        fit: BoxFit.contain, gaplessPlayback: true),
                    if (_videoReady && _video != null)
                      // Cross-fades in over a frame it is identical to, so the
                      // hand-off is invisible.
                      AnimatedOpacity(
                        duration: const Duration(milliseconds: 260),
                        opacity: 1,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: SizedBox(
                            width: _video!.value.size.width,
                            height: _video!.value.size.height,
                            child: VideoPlayer(_video!),
                          ),
                        ),
                      ),
                  ],
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
