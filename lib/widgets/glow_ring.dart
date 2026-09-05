import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import 'om_tappable.dart';

/// A lit disc inside two thin halo rings.
///
/// This replaces the orb on Home. The orb was a rendered 3D marble, and a
/// photoreal object dropped into a flat interface reads as a sticker no matter
/// how well it is drawn: it belonged to no other surface on the page, it was
/// the largest thing on the screen, and it was carrying a tap target nobody
/// could see was a tap target.
///
/// This is the same idea built out of the interface instead of on top of it.
/// The rings are hairlines in the brand colour, the disc is a two-stop gradient
/// with one specular highlight, and the glow behind it is the same bloom the
/// page already uses. It reads as a control because it is shaped like one.
class GlowRing extends StatefulWidget {
  const GlowRing({
    super.key,
    required this.size,
    required this.icon,
    this.onTap,
    this.active = false,
    this.tint,
    this.semanticLabel,
  });

  final double size;
  final IconData icon;
  final VoidCallback? onTap;

  /// Working. The rings breathe outwards rather than the disc scaling, so the
  /// button does not move under a thumb that is still on it.
  final bool active;

  /// Defaults to the brand colour.
  final Color? tint;

  final String? semanticLabel;

  @override
  State<GlowRing> createState() => _GlowRingState();
}

class _GlowRingState extends State<GlowRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _ctrl.repeat();
  }

  @override
  void didUpdateWidget(GlowRing old) {
    super.didUpdateWidget(old);
    if (widget.active == old.active) return;
    // Settled rather than stopped dead, so the rings finish the pass they are
    // in instead of freezing mid-travel.
    widget.active ? _ctrl.repeat() : _ctrl.animateTo(1.0).then((_) {
      if (mounted && !widget.active) _ctrl.value = 0;
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tint = widget.tint ?? c.primary;
    final disc = widget.size * 0.62;

    final art = AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) => CustomPaint(
        painter: _HaloPainter(
          t: _ctrl.value,
          tint: tint,
          dark: context.isDark,
        ),
        child: child,
      ),
      child: Center(
        child: Container(
          width: disc,
          height: disc,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.lerp(tint, Colors.white, 0.28)!,
                tint,
                Color.lerp(tint, c.accent, 0.45)!,
              ],
              stops: const [0, 0.55, 1],
            ),
            boxShadow: [
              BoxShadow(
                color: tint.withValues(alpha: 0.45),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The specular highlight, offset up and left the way a light
              // above and behind the viewer would put it. Without this the
              // disc is a flat coloured circle.
              Positioned(
                top: disc * 0.1,
                left: disc * 0.16,
                child: Container(
                  width: disc * 0.42,
                  height: disc * 0.3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      Colors.white.withValues(alpha: 0.55),
                      Colors.white.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
              Icon(widget.icon, size: disc * 0.36, color: Colors.white),
            ],
          ),
        ),
      ),
    );

    final sized = SizedBox(width: widget.size, height: widget.size, child: art);
    if (widget.onTap == null) return sized;
    return Semantics(
      button: true,
      label: widget.semanticLabel,
      child: OmTappable(
        onTap: () {
          Haptics.medium();
          widget.onTap!();
        },
        feedback: OmTapFeedback.none,
        pressedScale: 0.94,
        child: sized,
      ),
    );
  }
}

class _HaloPainter extends CustomPainter {
  _HaloPainter({required this.t, required this.tint, required this.dark});

  final double t;
  final Color tint;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.width / 2;

    // The bloom. Drawn first and wider than the rings so the disc sits in
    // light rather than on top of it.
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = RadialGradient(colors: [
          tint.withValues(alpha: dark ? 0.30 : 0.22),
          tint.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: centre, radius: r)),
    );

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    // Two hairlines, and while working a third travelling outwards through
    // them. A ring that expands and fades says "going" without moving the
    // thing being pressed.
    for (final f in const [0.99, 0.78]) {
      canvas.drawCircle(centre, r * f,
          ring..color = tint.withValues(alpha: dark ? 0.34 : 0.26));
    }
    if (t > 0) {
      final travel = Curves.easeOut.transform(t);
      canvas.drawCircle(
        centre,
        r * (0.62 + 0.38 * travel),
        ring..color = tint.withValues(alpha: 0.45 * (1 - travel)),
      );
    }
  }

  @override
  bool shouldRepaint(_HaloPainter old) =>
      old.t != t || old.tint != tint || old.dark != dark;
}

/// A thin progress ring, for the stat cards.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.size,
    this.stroke = 4,
    this.tint,
  });

  final double value;
  final double size;
  final double stroke;
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return SizedBox(
      width: size,
      height: size,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeOutCubic,
        builder: (context, v, _) => CustomPaint(
          painter: _RingPainter(
            value: v,
            track: c.border,
            tint: tint ?? c.primary,
            stroke: stroke,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.value,
    required this.track,
    required this.tint,
    required this.stroke,
  });

  final double value;
  final Color track;
  final Color tint;
  final double stroke;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = (size.width - stroke) / 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(rect.center, r, p..color = track);
    if (value <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: rect.center, radius: r),
      -math.pi / 2,
      2 * math.pi * value,
      false,
      p..color = tint,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.value != value || old.tint != tint || old.track != track;
}
