import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/theme/app_colors.dart';

/// The rotating record at the centre of the music card.
///
/// Artwork in a glass ring, turning while the track plays and easing to a stop
/// when it does not, with the elapsed fraction drawn as an arc around it. The
/// turning is the only "is it playing?" signal that reads at a glance, which
/// matters on a screen someone is deliberately not staring at.
class MusicDisc extends StatefulWidget {
  const MusicDisc({
    super.key,
    required this.artworkUrl,
    required this.playing,
    required this.progress,
    this.size = 188,
  });

  /// Cover art. Null falls back to a note glyph rather than an empty hole.
  final String? artworkUrl;

  final bool playing;

  /// 0..1, or null when the duration is not known yet.
  final double? progress;

  final double size;

  @override
  State<MusicDisc> createState() => _MusicDiscState();
}

class _MusicDiscState extends State<MusicDisc>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin = AnimationController(
    vsync: this,
    // One turn every twelve seconds: present when you look at it, and far too
    // slow to pull the eye away from what you are meant to be doing.
    duration: const Duration(seconds: 12),
  );

  @override
  void initState() {
    super.initState();
    if (widget.playing) _spin.repeat();
  }

  @override
  void didUpdateWidget(MusicDisc old) {
    super.didUpdateWidget(old);
    if (widget.playing == old.playing) return;
    if (widget.playing) {
      _spin.repeat();
    } else {
      // Stop where it stands. Snapping back to zero would read as "reset", and
      // the disc's angle is a small piece of continuity across a pause.
      _spin.stop();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final s = widget.size;

    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The glass ring the record sits in.
          Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  c.surfaceAlt.withValues(alpha: 0.9),
                  c.surface.withValues(alpha: 0.6),
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: c.shadow.withValues(alpha: 0.18),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
          ),
          // Elapsed, as an arc just inside the ring.
          CustomPaint(
            size: Size(s, s),
            painter: _ProgressRing(
              progress: widget.progress,
              track: c.ringTrack,
              fill: c.primary,
            ),
          ),
          RotationTransition(
            turns: _spin,
            child: Container(
              width: s * 0.68,
              height: s * 0.68,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c.surfaceAlt,
                border: Border.all(color: c.border.withValues(alpha: 0.6)),
              ),
              clipBehavior: Clip.antiAlias,
              child: _artwork(c),
            ),
          ),
          // The spindle, which is what makes it read as a record rather than a
          // circular crop of a photo.
          Container(
            width: s * 0.11,
            height: s * 0.11,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.surface,
              border: Border.all(color: c.border),
            ),
          ),
        ],
      ),
    );
  }

  Widget _artwork(OmColors c) {
    final url = widget.artworkUrl;
    if (url == null) {
      return Icon(LucideIcons.music4, size: widget.size * 0.22, color: c.text2);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      // Artwork is decoration. A broken load must not leave a hole where the
      // record should be, and must never look like the player has failed.
      errorBuilder: (_, __, ___) =>
          Icon(LucideIcons.music4, size: widget.size * 0.22, color: c.text2),
      loadingBuilder: (ctx, child, progress) =>
          progress == null ? child : ColoredBox(color: c.surfaceAlt),
    );
  }
}

class _ProgressRing extends CustomPainter {
  const _ProgressRing({
    required this.progress,
    required this.track,
    required this.fill,
  });

  final double? progress;
  final Color track;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final centre = rect.center;
    final radius = size.width / 2 - 7;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = track;
    canvas.drawCircle(centre, radius, base);

    final p = progress;
    if (p == null || p <= 0) return;

    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = fill;
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: radius),
      -math.pi / 2, // twelve o'clock
      2 * math.pi * p.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_ProgressRing old) =>
      old.progress != progress || old.fill != fill || old.track != track;
}
