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
/// **Motion is opt-in.** The orb holds a still frame until something asks it to
/// move. On Home that something is "refresh memory", so the orb moving means
/// the app is thinking - which is worth more than ambient motion that says
/// nothing, and costs no battery while it is saying nothing. The coach keeps
/// it running, because there the point *is* that someone is there.
///
/// The still frame is frame 0 of the video, verified identical rather than
/// eyeballed, so starting and stopping are cross-fades between two copies of
/// the same image and there is no jump in either direction.
///
/// Everything here is defensive, because a decoder is a thing that fails: if
/// the asset will not initialise the widget falls back to a static gradient orb
/// that looks near enough identical, and nobody sees an error.
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

  /// Drives the motion. The decoder is not created until this first goes true,
  /// so an orb that never plays never costs one.
  final bool playing;

  @override
  State<FluidOrb> createState() => _FluidOrbState();
}

class _FluidOrbState extends State<FluidOrb> {
  /// Long enough to read as the blob settling rather than the video being
  /// switched off. The frames either side are both this same object mid-morph,
  /// so the dissolve looks like one more thing it does.
  static const _settle = Duration(milliseconds: 700);

  VideoPlayerController? _controller;
  bool _ready = false;

  /// Whether the moving layer is faded in. Separate from [widget.playing]
  /// because it lags it on the way out - the video keeps rendering while it
  /// fades, so motion never stops on a hard cut.
  bool _showVideo = false;

  @override
  void initState() {
    super.initState();
    if (widget.video && widget.playing) _boot();
  }

  Future<void> _boot() async {
    if (_controller != null) return;
    final c = VideoPlayerController.asset('assets/video/fluid.mp4');
    _controller = c; // claim the slot so a second call cannot race this one
    try {
      await c.initialize();
      await c.setLooping(true);
      await c.setVolume(0);
      await c.play();
      if (!mounted) {
        await c.dispose();
        _controller = null;
        return;
      }
      setState(() {
        _ready = true;
        _showVideo = true;
      });
    } catch (_) {
      await c.dispose();
      _controller = null;
      // Leave _ready false: the still frame below is the whole recovery.
    }
  }

  @override
  void didUpdateWidget(FluidOrb old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) return;

    if (widget.playing) {
      if (!_ready) {
        _boot();
      } else {
        _controller?.play();
        setState(() => _showVideo = true);
      }
    } else {
      // Fade out first, and only stop the decoder once it is invisible. The
      // other order is a hard cut to a different frame.
      setState(() => _showVideo = false);
      Future<void>.delayed(_settle, () {
        if (mounted && !widget.playing) _controller?.pause();
      });
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

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // The resting state, always painted underneath. Nothing to jump to
          // when the video fades in over it, and nothing to jump from when it
          // fades back out.
          _StillFrame(size: size, glow: widget.glow),
          if (_ready && _controller != null)
            AnimatedOpacity(
              duration: _settle,
              curve: Curves.easeInOut,
              opacity: _showVideo ? 1 : 0,
              child: _feathered(_controller!),
            ),
        ],
      ),
    );
  }

  /// Feathered, not clipped.
  ///
  /// The source footage carries its own pale backdrop, so cropping it to a hard
  /// circle hangs a visible disc on the page and the blob stops floating.
  /// Fading the alpha out towards the edge instead lets the colour dissolve
  /// into whatever is behind it, which is the whole effect.
  Widget _feathered(VideoPlayerController c) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const RadialGradient(
          colors: [Colors.white, Colors.white, Colors.transparent],
          stops: [0.0, 0.55, 0.98],
        ).createShader(rect),
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: c.value.size.width,
            height: c.value.size.height,
            child: VideoPlayer(c),
          ),
        ),
      );
}

/// The orb at rest: frame 0 of the video as a still image, feathered the same
/// way so it occupies exactly the same shape as the moving version.
class _StillFrame extends StatelessWidget {
  const _StillFrame({required this.size, required this.glow});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const RadialGradient(
        colors: [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, 0.55, 0.98],
      ).createShader(rect),
      child: Image.asset(
        'assets/img/logo_static.png',
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // If even the still frame is missing, the painted orb is the last
        // resort - it looks near enough that nobody sees a failure.
        errorBuilder: (context, _, __) => _StaticOrb(size: size, glow: glow),
      ),
    );
  }
}

/// What you get when neither the video nor its still frame will load: the same
/// object, painted.
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
