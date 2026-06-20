import 'package:flutter/material.dart';

/// An [IndexedStack] that slides + fades the incoming tab when [index] changes,
/// giving macro-navigation a fluid, directional "page slide" feel (the new tab
/// glides in from the side you're moving toward) while still preserving every
/// tab's state (the stack keeps all children alive).
///
/// Collapses to a plain stack under reduce-motion.
class AnimatedIndexedStack extends StatefulWidget {
  const AnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.reduceMotion = false,
  });

  final int index;
  final List<Widget> children;
  final bool reduceMotion;

  @override
  State<AnimatedIndexedStack> createState() => _AnimatedIndexedStackState();
}

class _AnimatedIndexedStackState extends State<AnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 340),
  )..value = 1;

  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);

  /// +1 when moving to a later tab (slide in from the right), -1 when moving to
  /// an earlier tab (slide in from the left).
  double _direction = 1;

  @override
  void didUpdateWidget(AnimatedIndexedStack old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !widget.reduceMotion) {
      _direction = widget.index >= old.index ? 1 : -1;
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stack = IndexedStack(index: widget.index, children: widget.children);
    if (widget.reduceMotion) return stack;

    return AnimatedBuilder(
      animation: _curve,
      builder: (context, child) {
        final t = _curve.value;
        // Slide from a small offset toward zero; fade in alongside it.
        final dx = (1 - t) * 0.08 * _direction;
        return FractionalTranslation(
          translation: Offset(dx, 0),
          child: Opacity(opacity: t.clamp(0.0, 1.0), child: child),
        );
      },
      child: stack,
    );
  }
}
