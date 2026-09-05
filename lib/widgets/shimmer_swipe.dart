import 'package:flutter/material.dart';

/// A moving highlight swept across [child], for loading states.
///
/// [enabled] is not a convenience. This app has a reduce-motion setting and an
/// audience with a real stake in it, so a placeholder that animates regardless
/// of that setting is a bug rather than a flourish. Disabled, the controller
/// does not run at all, which also means no frames are spent on a widget that
/// is deliberately still.
class ShimmerSwipe extends StatefulWidget {
  const ShimmerSwipe({
    super.key,
    required this.child,
    this.enabled = true,
    this.strength = 0.2,
    this.period = const Duration(seconds: 3),
  });
  final Widget child;
  final bool enabled;

  /// Peak opacity of the band. The default is deliberately faint, for a sweep
  /// running under content that is already readable. A skeleton has nothing to
  /// compete with and needs considerably more than this to be seen at all.
  final double strength;

  /// One pass across the child. At the three second default a placeholder that
  /// is only up for a moment can be swapped out before the band has crossed
  /// it, so the whole animation amounts to a slight change in brightness.
  final Duration period;

  @override
  State<ShimmerSwipe> createState() => _ShimmerSwipeState();
}

class _ShimmerSwipeState extends State<ShimmerSwipe> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.enabled) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(ShimmerSwipe old) {
    super.didUpdateWidget(old);
    if (widget.enabled == old.enabled) return;
    widget.enabled ? _ctrl.repeat() : _ctrl.stop();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: widget.strength),
                Colors.white.withValues(alpha: 0.0),
              ],
              // Tighter than an even spread, so the highlight reads as a band
              // travelling across the card rather than the whole thing gently
              // brightening and dimming.
              stops: const [0.25, 0.5, 0.75],
              begin: const Alignment(-2.0, -0.3),
              end: const Alignment(2.0, 0.3),
              transform: _SlidingGradientTransform(_ctrl.value),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform(this.percent);
  final double percent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    // We want to slide from -width to +width
    final slide = (bounds.width * 3) * percent - bounds.width;
    return Matrix4.translationValues(slide, 0, 0);
  }
}
