import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';

/// A curved, draggable meter for picking a duration.
///
/// Replaces the grid of preset chips. Ten fixed buttons made the machine's
/// convenient numbers into the only allowed answers: if you know you have
/// thirty-five minutes before you have to leave, "25 or 30" is the app arguing
/// with you. This lets any value through, and still lands on round ones because
/// it snaps to [step].
///
/// Shaped after the reference: an arc rising left to right with the live value
/// under the centre tick, the travelled part drawn solid and the road ahead
/// dashed, so the number you are on reads as a position on a scale rather than
/// a figure in a box.
class OmMinuteDial extends StatefulWidget {
  const OmMinuteDial({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 5,
    this.max = 180,
    this.step = 5,
    this.height = 150,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;

  /// Values snap to this. Five minutes is fine enough to feel free and coarse
  /// enough that you never fight the drag for a single digit.
  final int step;

  final double height;

  @override
  State<OmMinuteDial> createState() => _OmMinuteDialState();
}

class _OmMinuteDialState extends State<OmMinuteDial> {
  /// Horizontal pixels per step. Wide enough that a deliberate drag moves a
  /// few values, not thirty.
  static const _pxPerStep = 26.0;

  double _accum = 0;

  void _drag(double dx) {
    _accum += dx;
    // Dragging left (negative dx) should raise the number, the way a physical
    // wheel rolls the far side of the dial towards you.
    final steps = (-_accum / _pxPerStep).truncate();
    if (steps == 0) return;
    _accum += steps * _pxPerStep;
    final next = (widget.value + steps * widget.step)
        .clamp(widget.min, widget.max)
        .toInt();
    if (next != widget.value) {
      Haptics.select();
      widget.onChanged(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _accum = 0,
      onHorizontalDragUpdate: (d) => _drag(d.delta.dx),
      // A tap on either side nudges one step, so the dial is usable without a
      // drag at all - fine motor control is not a fair thing to require.
      onTapUp: (d) {
        final mid = context.size!.width / 2;
        final delta = d.localPosition.dx < mid ? -widget.step : widget.step;
        final next = (widget.value + delta).clamp(widget.min, widget.max).toInt();
        if (next != widget.value) {
          Haptics.select();
          widget.onChanged(next);
        }
      },
      child: SizedBox(
        height: widget.height,
        width: double.infinity,
        child: CustomPaint(
          painter: _DialPainter(
            value: widget.value,
            min: widget.min,
            max: widget.max,
            step: widget.step,
            ink: c.text,
            faint: c.text2.withValues(alpha: 0.45),
            ghost: c.text2.withValues(alpha: 0.16),
            accent: c.primary,
          ),
          child: Center(
            child: Padding(
              padding: EdgeInsets.only(top: widget.height * 0.28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${widget.value}',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 40,
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'minutes',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: c.text2,
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.ink,
    required this.faint,
    required this.ghost,
    required this.accent,
  });

  final int value, min, max, step;
  final Color ink, faint, ghost, accent;

  /// How many steps are visible either side of the centre.
  static const _window = 5;

  @override
  void paint(Canvas canvas, Size size) {
    // The arc is a slice of a circle far below the widget, so the curve across
    // the visible width is gentle rather than a bowl.
    final radius = size.width * 1.15;
    final centre = Offset(size.width / 2, size.height * 0.30 + radius);

    double angleFor(double slot) => -math.pi / 2 + (slot * 0.052);
    Offset pointAt(double slot, double r) {
      final a = angleFor(slot);
      return centre + Offset(math.cos(a) * r, math.sin(a) * r);
    }

    final solid = Paint()
      ..color = ink
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final ahead = Paint()
      ..color = ghost
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // ── The road travelled: solid from the left edge up to the current value.
    final travelled = Path();
    for (var i = -_window; i <= 0; i++) {
      final p = pointAt(i.toDouble(), radius);
      i == -_window ? travelled.moveTo(p.dx, p.dy) : travelled.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(travelled, solid);

    // ── The road ahead: dashed, so it reads as "there is more" without
    // competing with where you are.
    for (var i = 0; i < _window * 4; i++) {
      final from = pointAt(i * 0.25, radius);
      final to = pointAt(i * 0.25 + 0.13, radius);
      if (i.isEven) canvas.drawLine(from, to, ahead);
    }

    // ── Endpoint dots, as in the reference.
    canvas.drawCircle(pointAt(-_window.toDouble(), radius), 5, Paint()..color = ink);
    canvas.drawCircle(pointAt(_window.toDouble(), radius), 5, Paint()..color = ghost);

    // ── The value marker: a filled node on the arc under the centre tick.
    canvas.drawCircle(pointAt(0, radius), 8.5, Paint()..color = accent);
    canvas.drawCircle(
      pointAt(0, radius),
      8.5,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // ── The centre tick above the arc, marking the read position.
    final tickTop = pointAt(0, radius - 34);
    final tickBottom = pointAt(0, radius - 18);
    canvas.drawLine(
      tickTop,
      tickBottom,
      Paint()
        ..color = ink
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round,
    );

    // ── Neighbouring values, greyed, so the scale is legible at a glance.
    for (final offset in [-_window, _window]) {
      final v = value + offset * step;
      if (v < min || v > max) continue;
      final anchor = pointAt(offset.toDouble(), radius - 30);
      final tp = TextPainter(
        text: TextSpan(
          text: '$v',
          style: TextStyle(
            color: faint,
            fontSize: 15,
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, anchor - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.value != value;
}
