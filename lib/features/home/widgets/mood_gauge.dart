import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../providers/mood_provider.dart';

/// The app's read on how you are doing, as a dial.
///
/// A dial and not a bar, because a bar reads as progress and there is no such
/// thing as progress through a mood. The arc is open at the bottom and the
/// needle is free to sit anywhere on it, including nowhere: with no reading
/// yet the track is drained and there is no needle at all, since a needle
/// parked at the middle is a claim that you are "okay", and that is exactly
/// the wrong thing to tell somebody who is not.
///
/// The light on the knob sits off-centre, matching the mood orbs, so the two
/// read as the same material.
class MoodGauge extends StatelessWidget {
  const MoodGauge({
    super.key,
    required this.mood,
    this.size = 132,
    this.pending = false,
  });

  /// null draws the empty dial.
  final Mood? mood;
  final double size;

  /// A reading is being made right now. The track breathes rather than showing
  /// a spinner: nothing here is urgent enough to earn one.
  final bool pending;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final m = mood;
    final tint = m == null
        ? Color.lerp(c.text2, c.surfaceAlt, 0.5)!
        : Color.lerp(c.accent, c.primary, m.value)!;

    return SizedBox(
      width: size,
      // The arc is open at the bottom but drops below the horizontal on both
      // ends, so the box is taller than a half circle and shorter than a full
      // one. Getting this wrong clips the ends off and the dial reads as a
      // broken ring. See [_GaugePainter._start].
      height: size * _GaugePainter.heightRatio,
      child: TweenAnimationBuilder<double>(
        // Slow and eased, so the needle settles like a physical one rather
        // than snapping to the new verdict.
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        tween: Tween(end: m == null ? 0.0 : m.value),
        builder: (context, v, _) => CustomPaint(
          painter: _GaugePainter(
            value: m == null ? null : v,
            tint: tint,
            track: c.ringTrack,
            pending: pending,
          ),
          // The word goes inside the dial, where the hole is. A gauge with an
          // empty middle is a gauge missing its reading: the arc says how far
          // along the scale, and only the word says what that means.
          child: Center(
            child: Padding(
              // Nudged up: the arc's centre of mass is above the box's, since
              // the opening is at the bottom.
              padding: EdgeInsets.only(bottom: size * 0.1),
              child: Text(
                m?.label ?? '—',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: m == null ? c.text2 : tint,
                  fontSize: size * 0.155,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({
    required this.value,
    required this.tint,
    required this.track,
    required this.pending,
  });

  /// 0..1, or null for the empty dial.
  final double? value;
  final Color tint;
  final Color track;
  final bool pending;

  /// The arc runs from lower-left to lower-right, leaving the bottom open.
  static const _start = math.pi * 0.82;
  static const _sweep = math.pi * 1.36;

  /// How tall the dial is relative to its width: the top of the circle down to
  /// the lowest point of the arc, which is its two ends, plus the stroke.
  static final double heightRatio =
      (1 + math.sin(_start)) / 2 * 0.925 + 0.075;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final r = (size.width - stroke) / 2;
    final centre = Offset(size.width / 2, r + stroke / 2);
    final rect = Rect.fromCircle(center: centre, radius: r);

    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..color = track.withValues(alpha: pending ? 0.5 : 1),
    );

    final v = value;
    if (v == null) return;

    // The fill runs coral to purple across the whole arc, not just the filled
    // part, so "low" is always the same colour wherever the needle stops.
    canvas.drawArc(
      rect,
      _start,
      _sweep * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = stroke
        ..shader = SweepGradient(
          startAngle: _start,
          endAngle: _start + _sweep,
          colors: [
            Color.lerp(tint, Colors.white, 0.34)!,
            tint,
          ],
        ).createShader(rect),
    );

    // The knob, lit from the upper left like the mood orbs.
    final angle = _start + _sweep * v;
    final knob = centre + Offset(math.cos(angle) * r, math.sin(angle) * r);
    final kr = stroke * 0.92;
    canvas
      ..drawCircle(
          knob,
          kr * 1.5,
          Paint()
            ..color = tint.withValues(alpha: 0.32)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, kr * 0.8))
      ..drawCircle(
        knob,
        kr,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.45),
            radius: 0.95,
            colors: [
              Color.lerp(tint, Colors.white, 0.78)!,
              tint,
              Color.lerp(tint, const Color(0xFF1B1033), 0.3)!,
            ],
            stops: const [0, 0.52, 1],
          ).createShader(Rect.fromCircle(center: knob, radius: kr)),
      );
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value ||
      old.tint != tint ||
      old.track != track ||
      old.pending != pending;
}
