import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
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
  static final double heightRatio = (1 + math.sin(_start)) / 2 * 0.925 + 0.075;

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

/// The same dial, but you drive the needle.
///
/// The check-in used to be five buttons in a row; this is the one dial the app
/// already speaks in, made to be dragged. You sweep the knob around the arc and
/// the reading swaps under your thumb - snapping to the five moods with a tick
/// each, the word and the colour changing live - so setting how you feel is one
/// continuous gesture rather than picking a face off a shelf.
///
/// It snaps rather than reading a raw angle: a mood is one of five things, not a
/// point on a continuum, so a knob that could stop between "low" and "okay"
/// would be claiming a precision the scale does not have. The knob still glides
/// between the stops, so the motion stays smooth even though the value does not.
class MoodDialPicker extends StatefulWidget {
  const MoodDialPicker({
    super.key,
    required this.initial,
    required this.onChanged,
    this.size = 232,
  });

  /// The mood to start on - the existing check-in when changing it, or null for
  /// a fresh one, which starts as an empty dial with no needle to prejudge you.
  final Mood? initial;
  final ValueChanged<Mood> onChanged;
  final double size;

  @override
  State<MoodDialPicker> createState() => _MoodDialPickerState();
}

class _MoodDialPickerState extends State<MoodDialPicker> {
  Mood? _sel;

  @override
  void initState() {
    super.initState();
    _sel = widget.initial;
  }

  /// Touch anywhere on the dial → the nearest mood. The arc is open at the
  /// bottom, so a touch that lands in that gap is resolved to whichever end it
  /// is closer to rather than being ignored.
  void _pick(Offset local, Size box) {
    final stroke = box.width * 0.075;
    final r = (box.width - stroke) / 2;
    final centre = Offset(box.width / 2, r + stroke / 2);

    // A dead zone around the hub. Near the centre the angle to the touch swings
    // wildly for a tiny movement, so a drag dragged straight across the middle
    // rather than along the ring would snap between far-apart moods. Ignoring
    // the inner disc keeps every update coming from out on the arc, where the
    // angle is stable and the gesture actually means something.
    final reach = (local - centre).distance;
    if (reach < r * 0.4) return;

    var a = math.atan2(local.dy - centre.dy, local.dx - centre.dx);
    // Clockwise distance travelled along the arc from its start.
    var cw = a - _GaugePainter._start;
    while (cw < 0) {
      cw += 2 * math.pi;
    }

    const sweep = _GaugePainter._sweep;
    final double t;
    if (cw <= sweep) {
      t = cw / sweep;
    } else {
      // In the bottom gap: nearer the end (great) or the start (rough)?
      const gap = 2 * math.pi - sweep;
      t = (cw - sweep) < gap / 2 ? 1.0 : 0.0;
    }

    // Nearest of the five by value (rough .2 … great 1.0).
    var best = Mood.values.first;
    var bestD = double.infinity;
    for (final m in Mood.values) {
      final d = (m.value - t).abs();
      if (d < bestD) {
        bestD = d;
        best = m;
      }
    }

    if (best != _sel) {
      Haptics.select();
      setState(() => _sel = best);
      widget.onChanged(best);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final box = Size(widget.size, widget.size * _GaugePainter.heightRatio);
    final m = _sel;
    final tint = m == null
        ? Color.lerp(c.text2, c.surfaceAlt, 0.5)!
        : Color.lerp(c.accent, c.primary, m.value)!;

    // A raw Listener, not a GestureDetector: this dial lives inside a
    // drag-to-dismiss bottom sheet, and a pan recogniser here would fight the
    // sheet for every downward drag. Listener takes the pointer stream directly
    // without entering the gesture arena, so the knob always follows the thumb
    // and the sheet still dismisses from everywhere else.
    // The Listener picks the mood; the GestureDetector around it exists only to
    // claim vertical drags so the sheet cannot.
    //
    // Listener alone was not enough. It stays out of the gesture arena, which
    // is what lets the knob follow the thumb - but it also means the sheet's
    // drag-to-dismiss recogniser won every vertical drag uncontested. The whole
    // sheet then travelled with the finger, so localPosition barely changed
    // relative to the dial and the selection never moved off its starting
    // stop. Tapping worked because a tap has no drag for the sheet to take,
    // which is exactly the difference that was reported.
    //
    // The drag callbacks are deliberately empty: winning the arena is the
    // entire job, and the picking is already handled by the pointer stream.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // These both CLAIM the vertical drag and act on it. Claiming alone would
      // be enough in theory - Listener sits outside the arena and still sees
      // every raw pointer move - but relying on that is relying on a subtlety,
      // and this is the gesture that was broken. Picking here too means the
      // selection follows the thumb whichever path the events take.
      onVerticalDragStart: (d) => _pick(d.localPosition, box),
      onVerticalDragUpdate: (d) => _pick(d.localPosition, box),
      onVerticalDragEnd: (_) {},
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) => _pick(e.localPosition, box),
        onPointerMove: (e) => _pick(e.localPosition, box),
        child: SizedBox(
          width: box.width,
          height: box.height,
          child: TweenAnimationBuilder<double>(
            // Quick enough to feel like the knob is under the thumb, eased enough
            // that the jump between two stops still glides.
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            tween: Tween(end: m == null ? 0.0 : m.value),
            builder: (context, v, _) => CustomPaint(
              painter: _GaugePainter(
                value: m == null ? null : v,
                tint: tint,
                track: c.ringTrack,
                pending: false,
              ),
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: widget.size * 0.1),
                  child: Text(
                    m?.label ?? 'drag to set',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: m == null ? c.text2 : tint,
                      fontSize: widget.size * (m == null ? 0.075 : 0.155),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
