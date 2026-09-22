import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';

/// "It is composing something", shown as a cloud over the coach's head.
///
/// The old indicator was three dots that bobbed on a sine wave inside a pill
/// stuck to the avatar's shoulder. It moved, technically, and it still read as
/// static: every dot travelled the same distance at the same speed forever, so
/// after half a second there was nothing left to look at.
///
/// What messaging apps actually do is different in three ways, and all three
/// matter. The bubble arrives, rather than being there: it pops in with a
/// little overshoot, so something happens at the moment the coach starts
/// thinking. The dots scale and fade rather than only moving, which reads as
/// breathing rather than as a conveyor belt. And the wave has a pause in it,
/// so the eye gets a beat of rest and the next cycle is an event again.
class ThinkingCloud extends StatefulWidget {
  const ThinkingCloud({
    super.key,
    required this.visible,
    required this.colour,
    this.width = 62,
  });

  /// The coach is composing. Going false plays the cloud out rather than
  /// cutting it, so the first words do not arrive on top of a hard disappear.
  final bool visible;

  /// The agent's own accent, so the cloud belongs to whoever is speaking.
  final Color colour;

  final double width;

  @override
  State<ThinkingCloud> createState() => _ThinkingCloudState();
}

class _ThinkingCloudState extends State<ThinkingCloud>
    with TickerProviderStateMixin {
  /// One continuous controller for the dots. Never restarted, so the wave does
  /// not jump when the widget rebuilds mid-cycle.
  late final AnimationController _wave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  /// The pop. Separate, because arriving and idling are different motions and
  /// driving both from one clock makes both worse.
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 160),
  );

  final _player = AudioPlayer();
  int _lastTick = -1;

  @override
  void initState() {
    super.initState();
    _wave.repeat();
    _wave.addListener(_maybeTick);
    if (widget.visible) _pop.forward();
    // Low latency matters more than anything else for a tick: the default
    // mode reloads the file per play and lands tens of milliseconds late,
    // which turns a rhythm into a stumble.
    _player.setPlayerMode(PlayerMode.lowLatency);
    _player.setReleaseMode(ReleaseMode.stop);
  }

  @override
  void didUpdateWidget(covariant ThinkingCloud old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      widget.visible ? _pop.forward() : _pop.reverse();
    }
  }

  @override
  void dispose() {
    _wave.removeListener(_maybeTick);
    _wave.dispose();
    _pop.dispose();
    _player.dispose();
    super.dispose();
  }

  /// One tick per cycle, on the first dot, and only while actually visible.
  ///
  /// Per cycle rather than per dot: three ticks a second is a woodpecker, and
  /// the point is a heartbeat somebody can ignore.
  void _maybeTick() {
    if (!mounted || !widget.visible) return;
    final cycle = (_wave.value * 1).floor();
    if (cycle == _lastTick) return;
    _lastTick = cycle;
    if (_wave.value > 0.05) return;

    final settings = context.read<SettingsProvider>();
    if (!settings.typingSound || settings.reduceMotion) return;
    // Failure here is silent on purpose. A missing asset or a busy audio
    // session must never take the chat down with it.
    _player.play(AssetSource('sfx/type_tick.wav'), volume: 0.35).catchError(
      (Object e) {
        debugPrint('[chat] tick failed: $e');
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final still = context.watch<SettingsProvider>().reduceMotion;

    return AnimatedBuilder(
      animation: Listenable.merge([_wave, _pop]),
      builder: (context, _) {
        final pop = Curves.easeOutBack.transform(_pop.value.clamp(0.0, 1.0));
        if (_pop.value == 0) return const SizedBox.shrink();

        return Opacity(
          opacity: _pop.value.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 0.6 + 0.4 * pop,
            // Grows out of the top of the head rather than from its own middle.
            alignment: Alignment.bottomCenter,
            child: CustomPaint(
              painter: _CloudPainter(
                fill: c.surface,
                shadow: c.shadow.withValues(alpha: 0.18),
              ),
              child: SizedBox(
                width: widget.width,
                height: widget.width * 0.52,
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < 3; i++) ...[
                        if (i > 0) SizedBox(width: widget.width * 0.075),
                        _Dot(
                          amount: still ? 0.5 : _dotAt(i),
                          colour: widget.colour,
                          size: widget.width * 0.13,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Where dot [i] is in its own rise and fall, 0 to 1.
  ///
  /// The wave occupies the first 70% of the cycle and the rest is a rest, so
  /// there is a beat of stillness before it starts again.
  double _dotAt(int i) {
    const span = 0.7;
    const stagger = 0.16;
    final start = i * stagger;
    final local = (_wave.value - start) / (span - 2 * stagger);
    if (local < 0 || local > 1) return 0;
    return math.sin(local * math.pi);
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.amount, required this.colour, required this.size});

  /// 0 is resting, 1 is the top of the rise.
  final double amount;
  final Color colour;
  final double size;

  @override
  Widget build(BuildContext context) {
    // Scale and opacity together, not position. A dot that only moves reads as
    // a mechanism; one that swells reads as breathing.
    final s = 0.72 + 0.48 * amount;
    return Transform.translate(
      offset: Offset(0, -size * 0.28 * amount),
      child: Transform.scale(
        scale: s,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: colour.withValues(alpha: 0.45 + 0.55 * amount),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

/// A rounded bubble with a tail, and two small bubbles trailing off it, which
/// is what makes it read as a thought rather than as a label.
class _CloudPainter extends CustomPainter {
  _CloudPainter({required this.fill, required this.shadow});

  final Color fill;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.height / 2),
    );

    final paint = Paint()..color = fill;
    canvas.drawShadow(
      Path()..addRRect(body),
      shadow,
      3,
      false,
    );
    canvas.drawRRect(body, paint);

    // The tail: two shrinking circles heading down towards the head, offset to
    // one side so the cloud looks like it is rising off the avatar rather than
    // balanced on it.
    final cx = size.width * 0.3;
    canvas.drawCircle(
        Offset(cx, size.height + size.height * 0.16), size.height * 0.13, paint);
    canvas.drawCircle(
        Offset(cx - size.height * 0.16, size.height + size.height * 0.42),
        size.height * 0.08,
        paint);
  }

  @override
  bool shouldRepaint(covariant _CloudPainter old) =>
      old.fill != fill || old.shadow != shadow;
}
