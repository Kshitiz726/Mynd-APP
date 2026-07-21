import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// Mynd's face: a slow, living blob of colour, generated on the GPU.
///
/// A still gradient is a logo; this is a presence. The coach is the one part of
/// the app that is supposed to feel like someone is there, and the cheapest
/// honest way to say so is motion that never quite repeats where you expect.
///
/// **This used to be a video**, and being a video cost three things. A 519 KB
/// asset in the bundle. A hardware decoder running whenever it was on screen.
/// And a loop - which meant a seam, which had to be hidden by crossfading the
/// tail into the head, which is a whole pipeline of work to paper over the fact
/// that the file ends.
///
/// A fragment shader has none of those. There is no file to decode, the work
/// happens on the GPU where this kind of work belongs, and it does not loop at
/// all: the motion comes from sine fields at unrelated frequencies, so it never
/// returns to a previous state and there is no seam to hide. The colours are
/// uniforms rather than pixels, so the orb is brand-coloured by construction
/// and follows the theme into dark mode instead of being a fixed image that
/// happens to be roughly the right hue.
///
/// **Motion is opt-in.** The orb holds a still frame until something asks it to
/// move. On Home that something is "refresh memory", so the orb moving means
/// the app is thinking. A paused orb costs one shader evaluation and then
/// nothing, because a still frame is just this shader at a fixed time.
class FluidOrb extends StatefulWidget {
  const FluidOrb({
    super.key,
    this.size = 108,
    this.glow = true,
    this.playing = true,
    this.video = true,
  });

  /// The same object, held still.
  ///
  /// Kept as a named constructor because call sites use it, but it no longer
  /// means anything expensive - a still orb is the same shader with the clock
  /// stopped.
  const FluidOrb.still({super.key, this.size = 28, this.glow = false})
      : playing = false,
        video = false;

  final double size;

  /// Retained for API compatibility with the video implementation. Motion is
  /// governed by [playing]; this only forces the orb to stay still.
  final bool video;

  /// The coloured bloom underneath. Wanted on the hero, not on a 28px avatar
  /// sitting inside a list.
  final bool glow;

  /// Drives the motion.
  final bool playing;

  @override
  State<FluidOrb> createState() => _FluidOrbState();
}

class _FluidOrbState extends State<FluidOrb>
    with SingleTickerProviderStateMixin {
  /// Long enough that the phase never visibly resets; the shader's own motion
  /// is not tied to this period, it just needs a monotonic clock.
  static const _period = Duration(seconds: 120);

  /// Matches the settle used when motion stops, so starting and stopping feel
  /// like the same gesture in reverse.
  static const _settle = Duration(milliseconds: 700);

  /// One program for the whole app. Compiling it per orb would be wasteful and,
  /// on the coach screen, visible.
  static Future<ui.FragmentProgram>? _program;

  ui.FragmentShader? _shader;

  late final AnimationController _clock = AnimationController(
    vsync: this,
    duration: _period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _clock.repeat();
    _load();
  }

  Future<void> _load() async {
    _program ??= ui.FragmentProgram.fromAsset('shaders/fluid_orb.frag');
    try {
      final program = await _program!;
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (e) {
      // A shader that will not compile is a device problem, not a user
      // problem: the painted orb below looks near enough and nobody sees an
      // error. Reset so a later orb can try again on a fresh program.
      debugPrint('[orb] shader unavailable: $e');
      _program = null;
    }
  }

  @override
  void didUpdateWidget(FluidOrb old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) return;
    if (widget.playing) {
      _clock.repeat();
    } else {
      // Let the current motion ease out rather than freezing on the frame the
      // press happened to end on.
      _clock.animateTo(
        _clock.value + 0.01,
        duration: _settle,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  void dispose() {
    _clock.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final shader = _shader;

    Widget orb;
    if (shader == null) {
      orb = _StaticOrb(size: widget.size, glow: widget.glow);
    } else {
      orb = AnimatedBuilder(
        animation: _clock,
        builder: (context, _) => CustomPaint(
          size: Size.square(widget.size),
          painter: _OrbPainter(
            shader: shader,
            // Seconds. The shader only needs a clock that moves forward.
            time: _clock.value * _period.inSeconds,
            primary: c.primary,
            accent: c.accent,
            flow: c.flow,
          ),
        ),
      );
    }

    if (!widget.glow) {
      return SizedBox(width: widget.size, height: widget.size, child: orb);
    }
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: 0.28),
              blurRadius: widget.size * 0.30,
              spreadRadius: -widget.size * 0.08,
              offset: Offset(0, widget.size * 0.10),
            ),
          ],
        ),
        child: orb,
      ),
    );
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter({
    required this.shader,
    required this.time,
    required this.primary,
    required this.accent,
    required this.flow,
  });

  final ui.FragmentShader shader;
  final double time;
  final Color primary;
  final Color accent;
  final Color flow;

  @override
  void paint(Canvas canvas, Size size) {
    // Uniforms are set by flat float index, in declaration order: uSize is two
    // floats, uTime one, then three colours of three each.
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time)
      ..setFloat(3, primary.r)
      ..setFloat(4, primary.g)
      ..setFloat(5, primary.b)
      ..setFloat(6, accent.r)
      ..setFloat(7, accent.g)
      ..setFloat(8, accent.b)
      ..setFloat(9, flow.r)
      ..setFloat(10, flow.g)
      ..setFloat(11, flow.b);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_OrbPainter old) =>
      old.time != time ||
      old.primary != primary ||
      old.accent != accent ||
      old.flow != flow;
}

/// What you get when the shader will not compile: the same object, painted.
class _StaticOrb extends StatelessWidget {
  const _StaticOrb({required this.size, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.42),
          radius: 0.95,
          colors: [
            Color.lerp(c.accent, Colors.white, 0.62)!,
            c.accent,
            c.primary,
            Color.lerp(c.primary, const Color(0xFF160C2E), 0.45)!,
          ],
          stops: const [0.0, 0.32, 0.72, 1.0],
        ),
      ),
    );
  }
}
