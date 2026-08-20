import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../models/energy_level.dart';
import '../providers/energy_provider.dart';

/// The OurMynd mascot - a soft gradient blob with dynamic eyes and mouth 
/// reflecting the user's current energy level, now with smooth animations!
class OmMascot extends StatelessWidget {
  const OmMascot({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final energy = context.watch<EnergyProvider>().current;
    
    final double targetMood = energy == EnergyLevel.high ? 0.0 : energy == EnergyLevel.low ? 1.0 : 2.0;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.primary, c.flow],
        ),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: 0.32),
            blurRadius: size * 0.22,
            offset: Offset(0, size * 0.08),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Soft top-left gloss so the blob reads glossy, not flat.
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  center: const Alignment(-0.45, -0.55),
                  radius: 0.95,
                  colors: [
                    Colors.white.withValues(alpha: 0.35),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.7],
                ),
              ),
            ),
          ),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(end: targetMood),
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            builder: (context, mood, _) {
              return SizedBox.expand(
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _MascotFacePainter(mood: mood),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MascotFacePainter extends CustomPainter {
  _MascotFacePainter({required this.mood});
  
  final double mood;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final eyeY = h * 0.40;
    final eyeR = w * 0.075;

    final double deadOpacity = (mood - 1.0).clamp(0.0, 1.0);
    final double aliveOpacity = 1.0 - deadOpacity;

    // Draw eyes based on energy
    if (aliveOpacity > 0.01) {
      final dot = Paint()..color = Colors.white.withValues(alpha: aliveOpacity);
      canvas.drawCircle(Offset(w * 0.36, eyeY), eyeR, dot);
      canvas.drawCircle(Offset(w * 0.64, eyeY), eyeR, dot);
    }
    
    if (deadOpacity > 0.01) {
      final xPaint = Paint()
        ..color = Colors.white.withValues(alpha: deadOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.05
        ..strokeCap = StrokeCap.round;
      
      final leftCenter = Offset(w * 0.36, eyeY);
      final rightCenter = Offset(w * 0.64, eyeY);
      final offset = eyeR * 0.8;
      
      canvas.drawLine(leftCenter - Offset(offset, offset), leftCenter + Offset(offset, offset), xPaint);
      canvas.drawLine(leftCenter - Offset(offset, -offset), leftCenter + Offset(offset, -offset), xPaint);
      
      canvas.drawLine(rightCenter - Offset(offset, offset), rightCenter + Offset(offset, offset), xPaint);
      canvas.drawLine(rightCenter - Offset(offset, -offset), rightCenter + Offset(offset, -offset), xPaint);
    }

    final mouth = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.07
      ..strokeCap = StrokeCap.round;

    // Morph the mouth using a quadratic bezier curve!
    // Control point Y interpolates from a deep smile (0.75), to flat (0.60), to a frown (0.45).
    final double controlY = mood <= 1.0 
        ? lerpDouble(h * 0.75, h * 0.60, mood)! 
        : lerpDouble(h * 0.60, h * 0.45, mood - 1.0)!;

    // The mouth ends also shift up slightly when frowning to look more natural
    final double endY = mood <= 1.0 
        ? lerpDouble(h * 0.52, h * 0.60, mood)! 
        : lerpDouble(h * 0.60, h * 0.65, mood - 1.0)!;

    final Path mouthPath = Path()
      ..moveTo(w * 0.35, endY)
      ..quadraticBezierTo(w * 0.5, controlY, w * 0.65, endY);

    canvas.drawPath(mouthPath, mouth);
  }

  @override
  bool shouldRepaint(covariant _MascotFacePainter oldDelegate) => oldDelegate.mood != mood;
}
