import 'package:flutter/material.dart';

import '../../../core/utils/om_icons.dart';

/// The badge on a focus room card.
///
/// It used to be a hairline Lucide outline on a flat tinted square, which at
/// 21px read as grey furniture: every room looked like every other room, and
/// nothing about the tile suggested there were people behind it.
///
/// Three changes carry the weight:
///
/// * a solid glyph on a **gradient** fill, so the badge has depth and the
///   room's own colour actually shows;
/// * a light bloom in the upper-left, which is what makes it read as an object
///   rather than a swatch;
/// * a **breathing halo** while anyone is in the room. Presence is the single
///   most useful thing a room tile can tell you, and motion says it before any
///   label does. It stops when the room is empty, so a quiet lobby is still.
class RoomGlyph extends StatefulWidget {
  const RoomGlyph({
    super.key,
    required this.iconName,
    required this.color,
    required this.live,
    this.size = 46,
  });

  final String iconName;
  final Color color;

  /// Whether anyone is currently in the room.
  final bool live;

  final double size;

  @override
  State<RoomGlyph> createState() => _RoomGlyphState();
}

class _RoomGlyphState extends State<RoomGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.live) _pulse.repeat();
  }

  @override
  void didUpdateWidget(RoomGlyph old) {
    super.didUpdateWidget(old);
    if (widget.live && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.live && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final tint = widget.color;

    final badge = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.34),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(tint, Colors.white, 0.34)!,
            tint,
            Color.lerp(tint, const Color(0xFF17102E), 0.28)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.38),
            blurRadius: size * 0.28,
            offset: Offset(0, size * 0.14),
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // The specular bloom that turns a swatch into an object.
          Positioned(
            top: -size * 0.18,
            left: -size * 0.18,
            child: Container(
              width: size * 0.8,
              height: size * 0.8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.42),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          Icon(OmIcons.solid(widget.iconName), size: size * 0.46, color: Colors.white),
        ],
      ),
    );

    if (!widget.live) return badge;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final t = Curves.easeOut.transform(_pulse.value);
        return Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // A ring expanding outwards and fading, once per cycle.
            Opacity(
              opacity: (1 - t) * 0.5,
              child: Container(
                width: size * (1 + t * 0.55),
                height: size * (1 + t * 0.55),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(size * 0.34 * (1 + t * 0.4)),
                  border: Border.all(color: tint.withValues(alpha: 0.7), width: 1.5),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: badge,
    );
  }
}
