import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../models/agent.dart';

/// What the avatar is doing, which is the only thing that drives its motion.
enum AgentMood {
  /// Sitting there. Breathing, and not much else.
  idle,

  /// The turn has been sent and nothing has come back yet.
  thinking,

  /// Tokens are arriving.
  speaking,
}

/// The agent's face, alive.
///
/// One controller, running continuously, with the three states reading
/// different things off the same clock. That matters: starting and stopping
/// controllers on a state change is what produces the little jolt where a
/// character snaps back to rest before it starts the next animation, and the
/// whole point of this is that it looks like something rather than like a
/// widget swapping.
///
/// Idle is a slow breath and a gentle bob. Thinking leans the head, bounces
/// faster and puts three dots above it - a character that is visibly working,
/// not a spinner sitting next to a picture. Speaking is a quicker, smaller
/// pulse with a ring that keeps time, so a long reply reads as ongoing rather
/// than as frozen.
class AgentAvatar extends StatefulWidget {
  const AgentAvatar({
    super.key,
    required this.agent,
    required this.size,
    this.mood = AgentMood.idle,
    this.showRing = true,
    this.onTap,
  });

  final Agent agent;
  final double size;
  final AgentMood mood;

  /// The accent ring. Off in dense places like a picker grid, where a dozen
  /// rings is noise.
  final bool showRing;

  final VoidCallback? onTap;

  @override
  State<AgentAvatar> createState() => _AgentAvatarState();
}

class _AgentAvatarState extends State<AgentAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    // A long period that the three states divide down into their own rhythms,
    // rather than three controllers to keep in step.
    duration: const Duration(milliseconds: 2400),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.agent;
    final s = widget.size;

    final face = AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        final (scale, dy, tilt) = switch (widget.mood) {
          // One slow breath per cycle, and a bob half a beat behind it so the
          // two never peak together and read as a single pulse.
          AgentMood.idle => (
              1 + 0.022 * math.sin(t * 2 * math.pi),
              -2.0 * math.sin(t * 2 * math.pi + 0.8),
              0.012 * math.sin(t * 2 * math.pi * 0.5),
            ),
          // Three times the rate, leaning into the thought.
          AgentMood.thinking => (
              1 + 0.045 * math.sin(t * 2 * math.pi * 3),
              -4.0 * math.sin(t * 2 * math.pi * 3).abs(),
              -0.075 + 0.03 * math.sin(t * 2 * math.pi * 1.5),
            ),
          // Small and quick, like speech rather than effort.
          AgentMood.speaking => (
              1 + 0.03 * math.sin(t * 2 * math.pi * 4),
              -1.5 * math.sin(t * 2 * math.pi * 4),
              0.02 * math.sin(t * 2 * math.pi * 2),
            ),
        };

        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.rotate(
            angle: tilt,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: ClipOval(
        child: Image.asset(
          a.asset,
          width: s,
          height: s,
          fit: BoxFit.cover,
          // A missing asset must not take the header down with it. The agent's
          // accent is a face of sorts: it still says which one is selected.
          errorBuilder: (_, __, ___) => Container(
            width: s,
            height: s,
            color: a.accent.withValues(alpha: 0.25),
            alignment: Alignment.center,
            child: Text(
              a.name.characters.first,
              style: TextStyle(
                fontSize: s * 0.42,
                fontWeight: FontWeight.w800,
                color: a.accent,
              ),
            ),
          ),
        ),
      ),
    );

    Widget out = SizedBox(
      width: s,
      height: s,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          if (widget.showRing)
            AnimatedBuilder(
              animation: _c,
              builder: (context, _) => CustomPaint(
                size: Size.square(s),
                painter: _RingPainter(
                  colour: a.accent,
                  t: _c.value,
                  mood: widget.mood,
                ),
              ),
            ),
          face,
          if (widget.mood == AgentMood.thinking)
            Positioned(
              top: -s * 0.14,
              right: -s * 0.04,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) =>
                    _ThinkingDots(t: _c.value, colour: a.accent, size: s * 0.3),
              ),
            ),
        ],
      ),
    );

    if (widget.onTap != null) {
      out = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: out,
      );
    }
    return Semantics(
      label: switch (widget.mood) {
        AgentMood.idle => '${a.name}, your coach',
        AgentMood.thinking => '${a.name} is thinking',
        AgentMood.speaking => '${a.name} is replying',
      },
      button: widget.onTap != null,
      child: out,
    );
  }
}

/// The ring around the face. Idle it is a faint static hairline; working, it is
/// an arc that travels, so there is a moving part even when the bob is at the
/// top or bottom of its travel and momentarily still.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.colour, required this.t, required this.mood});

  final Color colour;
  final double t;
  final AgentMood mood;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final centre = Offset(size.width / 2, size.height / 2);

    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.055
      ..color = colour.withValues(alpha: mood == AgentMood.idle ? 0.16 : 0.22);
    canvas.drawCircle(centre, r * 1.06, track);

    if (mood == AgentMood.idle) return;

    final sweep = mood == AgentMood.thinking ? math.pi * 0.5 : math.pi * 0.28;
    final speed = mood == AgentMood.thinking ? 2.0 : 3.0;
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.075
      ..strokeCap = StrokeCap.round
      ..color = colour.withValues(alpha: 0.85);

    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: r * 1.06),
      t * 2 * math.pi * speed,
      sweep,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.t != t || old.mood != mood || old.colour != colour;
}

/// Three dots in a little bubble, rising in turn. The thing a character does
/// while it thinks, rather than the thing a progress indicator does.
class _ThinkingDots extends StatelessWidget {
  const _ThinkingDots({
    required this.t,
    required this.colour,
    required this.size,
  });

  final double t;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: size * 0.22, vertical: size * 0.17),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(size),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.16),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: size * 0.13),
            Transform.translate(
              // A third of a cycle apart, so they rise as a wave rather than
              // together.
              offset: Offset(
                0,
                -size * 0.14 *
                    math.max(0, math.sin((t * 3 - i / 3) * 2 * math.pi)),
              ),
              child: Container(
                width: size * 0.16,
                height: size * 0.16,
                decoration: BoxDecoration(
                  color: colour.withValues(alpha: 0.9),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
