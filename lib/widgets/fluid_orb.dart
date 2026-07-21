import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../core/theme/app_colors.dart';

/// Mynd's face: a slow, living blob of colour, played from a looping video and
/// clipped to a circle.
///
/// A still gradient is a logo; this is a presence. The coach is the one part of
/// the app that is supposed to feel like someone is there, and the cheapest
/// honest way to say so is motion that never quite repeats where you expect.
///
/// Everything here is defensive, because a decoder is a thing that fails:
/// if the asset will not initialise the widget falls back to a static gradient
/// orb that looks near enough identical, and nobody sees an error.
class FluidOrb extends StatefulWidget {
  const FluidOrb({
    super.key,
    this.size = 108,
    this.glow = true,
    this.playing = true,
    this.video = true,
  });

  /// The same object, painted rather than decoded.
  ///
  /// A video decoder per orb is a real cost, and at avatar size nobody can see
  /// the motion anyway. So the hero plays and the small ones hold still, which
  /// keeps exactly one decoder alive on the screen at a time.
  const FluidOrb.still({super.key, this.size = 28, this.glow = false})
      : playing = false,
        video = false;

  final double size;

  /// Whether to decode the looping video at all.
  final bool video;

  /// The coloured bloom underneath. Wanted on the hero, not on a 28px avatar
  /// sitting inside a list.
  final bool glow;

  /// Paused orbs still render their first frame, so a quiet coach can sit
  /// still rather than churning battery in the background.
  final bool playing;

  @override
  State<FluidOrb> createState() => _FluidOrbState();
}

class _FluidOrbState extends State<FluidOrb> {
  VideoPlayerController? _controller;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (widget.video) _boot();
  }

  Future<void> _boot() async {
    final c = VideoPlayerController.asset('assets/video/fluid.mp4');
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      if (widget.playing) await c.play();
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _controller = c;
        _ready = true;
      });
    } catch (_) {
      await c.dispose();
      // Leave _ready false: the gradient fallback below is the whole recovery.
    }
  }

  @override
  void didUpdateWidget(FluidOrb old) {
    super.didUpdateWidget(old);
    if (widget.playing != old.playing && _ready) {
      widget.playing ? _controller?.play() : _controller?.pause();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    if (!_ready || _controller == null) {
      return SizedBox(
        width: size,
        height: size,
        child: _StaticOrb(size: size, glow: widget.glow),
      );
    }

    // Feathered, not clipped.
    //
    // The source footage carries its own pale backdrop, so cropping it to a
    // hard circle hangs a visible disc on the page and the blob stops floating.
    // Fading the alpha out towards the edge instead lets the colour dissolve
    // into whatever is behind it, which is the whole effect.
    return SizedBox(
      width: size,
      height: size,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const RadialGradient(
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.55, 0.98],
        ).createShader(rect),
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: _controller!.value.size.width,
            height: _controller!.value.size.height,
            child: VideoPlayer(_controller!),
          ),
        ),
      ),
    );
  }
}

/// What you get when the video will not play: the same object, holding still.
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
        boxShadow: glow
            ? [
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.30),
                  blurRadius: size * 0.32,
                  spreadRadius: -size * 0.06,
                  offset: Offset(0, size * 0.12),
                ),
              ]
            : null,
      ),
    );
  }
}
