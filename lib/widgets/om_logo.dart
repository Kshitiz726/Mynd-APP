import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// The OurMynd brand mark: a soft gradient squircle holding a minimal "focus
/// aura" glyph - two concentric rings around a centred mind-dot, with a single
/// peach accent satellite. Drawn entirely in code so it stays crisp at any size
/// and re-tints with the theme. Used on the login screen, headers and the
/// about/profile surfaces.
class OmLogo extends StatelessWidget {
  const OmLogo({super.key, this.size = 96, this.glow = true});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final r = size * 0.30; // squircle corner radius
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: c.brandGradient,
        borderRadius: BorderRadius.circular(r),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.42),
                  blurRadius: size * 0.5,
                  spreadRadius: -size * 0.06,
                  offset: Offset(0, size * 0.18),
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: _AuraPainter(accent: c.accent),
        // A faint top-left sheen for a glassy, premium finish.
        foregroundPainter: _SheenPainter(radius: r),
      ),
    );
  }
}

class _AuraPainter extends CustomPainter {
  _AuraPainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final s = size.shortestSide;

    final ringOuter = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..color = Colors.white.withValues(alpha: 0.35);
    final ringInner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.05
      ..color = Colors.white.withValues(alpha: 0.85);
    final dot = Paint()..color = Colors.white;
    final satellite = Paint()..color = accent;

    canvas.drawCircle(center, s * 0.32, ringOuter);
    canvas.drawCircle(center, s * 0.19, ringInner);
    canvas.drawCircle(center, s * 0.075, dot);

    // Peach satellite on the upper-right ring - the signature spark of focus.
    const ang = -math.pi / 4; // up-right
    final sat = center + Offset(math.cos(ang), math.sin(ang)) * (s * 0.32);
    canvas.drawCircle(sat, s * 0.055, satellite);
  }

  @override
  bool shouldRepaint(_AuraPainter old) => old.accent != accent;
}

class _SheenPainter extends CustomPainter {
  _SheenPainter({required this.radius});
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final sheen = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.center,
        colors: [Colors.white.withValues(alpha: 0.22), Colors.white.withValues(alpha: 0.0)],
      ).createShader(Offset.zero & size);
    canvas.drawRRect(rrect, sheen);
  }

  @override
  bool shouldRepaint(_SheenPainter old) => old.radius != radius;
}
