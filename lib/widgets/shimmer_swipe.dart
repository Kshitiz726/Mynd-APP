import 'package:flutter/material.dart';

class ShimmerSwipe extends StatefulWidget {
  const ShimmerSwipe({super.key, required this.child});
  final Widget child;

  @override
  State<ShimmerSwipe> createState() => _ShimmerSwipeState();
}

class _ShimmerSwipeState extends State<ShimmerSwipe> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 3),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.2),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.5, 1.0],
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
