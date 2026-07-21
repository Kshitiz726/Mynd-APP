import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/fluid_orb.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';
import '../../memory/memory_actions.dart';

/// The top of Home: Mynd itself, the day's count, and a way to make it think
/// again.
///
/// What was here before was a flat gradient circle with a drawn-on smile whose
/// mouth curved with your energy level, and a pill underneath naming that
/// energy. Two problems. The face was a sticker, not a presence, and it was the
/// first thing anyone saw. And the pill said "high energy" directly above cards
/// that already say how the day is going, so the most prominent thing on the
/// page was also the most redundant.
///
/// Now it is the same living orb the coach has, so Mynd has one face
/// everywhere, sitting in a slow aurora that drifts whether or not you touch
/// it. Touching it makes it answer. The pill is gone and a refresh sits in its
/// place, because "think about me again" is a thing worth having on the front
/// page and "you said you had energy" is not.
class MyndHero extends StatefulWidget {
  const MyndHero({super.key});

  @override
  State<MyndHero> createState() => _MyndHeroState();
}

class _MyndHeroState extends State<MyndHero> with TickerProviderStateMixin {
  /// The idle drift. Never stops, never repeats where you expect, because two
  /// rings turning at unrelated speeds do not come back into phase for a long
  /// time.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  /// The reload. Runs once per press and is what the orb is doing while the
  /// app actually re-reads you.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _busy = false;

  @override
  void dispose() {
    _drift.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_busy) return;
    Haptics.medium();
    setState(() => _busy = true);
    _pulse.repeat();
    try {
      // The two things the app believes about you, both rebuilt from the same
      // picture. Called directly rather than through the autopilot, which is
      // the point of a button: pressing it means now, not when the cooldown
      // says so.
      await refreshMemory(context, haptic: false, quiet: true);
      if (mounted) await readMood(context);
    } finally {
      if (mounted) {
        // Let the current turn finish rather than cutting the light off
        // mid-sweep, which is what makes a loading state feel mechanical.
        await _pulse.forward(from: _pulse.value);
        if (mounted) setState(() => _busy = false);
        _pulse.reset();
      }
    }
  }

  void _poke() {
    if (_busy) return;
    Haptics.light();
    _pulse.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final goals = context.watch<GoalProvider>().activeCount;
    final done = tasks.doneCount;
    final scheduled = tasks.daySchedule.length;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 176,
          child: OmTappable(
            onTap: _poke,
            feedback: OmTapFeedback.none,
            pressedScale: 0.97,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                // The aurora. Painted behind and wider than the orb, so the top
                // of the page has weather rather than a logo on a background.
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_drift, _pulse]),
                    builder: (context, _) => CustomPaint(
                      painter: _AuroraPainter(
                        t: _drift.value,
                        pulse: _pulse.value,
                        busy: _busy,
                        primary: c.primary,
                        accent: c.accent,
                        flow: c.flow,
                      ),
                    ),
                  ),
                ),
                // The orb and its badge share a box exactly the orb's size, so
                // the badge hangs off the rim. Positioned against the outer
                // stack it drifted inwards and sat across the face.
                SizedBox(
                  width: 124,
                  height: 124,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, child) {
                          // One breath in and out over the turn. Eased both
                          // ways, so it reads as the thing inhaling rather
                          // than as a scale animation playing.
                          final breath = math.sin(_pulse.value * math.pi);
                          return Transform.scale(
                            scale: 1 + 0.055 * Curves.easeInOut.transform(breath),
                            child: child,
                          );
                        },
                        child: const FluidOrb(size: 124),
                      ),
                      Positioned(
                        right: -14,
                        bottom: 2,
                        child: _StreakBadge(count: done),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('$done done today',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: 30)),
        const SizedBox(height: 4),
        Text('$scheduled scheduled · $goals goals',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: c.text2, fontWeight: FontWeight.w500)),
        const SizedBox(height: AppSpacing.lg),
        _ReloadButton(busy: _busy, spin: _pulse, onTap: _reload),
      ],
    );
  }
}

/// Streak, unchanged in substance: the count of what you finished today, worn
/// on the orb rather than listed under it.
class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c.accent, Color.lerp(c.accent, Colors.red, 0.25)!],
        ),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
              color: c.accent.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(OmIcons.byName('flame'), size: 15, color: Colors.white),
          const SizedBox(width: 4),
          Text('$count',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  )),
        ],
      ),
    );
  }
}

/// "Refresh memory" - re-read everything and rewrite what the app thinks.
///
/// A glass pill rather than a bare icon, and it says what it does. A lone
/// circular arrow on a home screen reads as "reload the page", which is a
/// browser idea and would promise the wrong thing.
///
/// It used to say "catch up", which was vaguer than the thing it actually
/// does: this calls refreshMemory and then re-reads your mood, so the honest
/// label is the one naming the memory it rewrites. It is also the only control
/// that starts the orb moving, and "catch up" gave no hint that pressing it
/// would make the app think.
class _ReloadButton extends StatelessWidget {
  const _ReloadButton({
    required this.busy,
    required this.spin,
    required this.onTap,
  });

  final bool busy;
  final Animation<double> spin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            // The brand-coloured lift stays on the outside of the glass: a
            // BackdropFilter is clipped, so a shadow drawn inside it would be
            // cut off at the pill's own edge.
            BoxShadow(
              color: c.primary.withValues(alpha: busy ? 0.26 : 0.12),
              blurRadius: busy ? 20 : 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: OmGlass(
          borderRadius: AppRadius.pill,
          blur: 18,
          // Opaque enough while working that the label stays readable over
          // whatever the page is doing behind it.
          opacity: busy ? 0.86 : 0.60,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: spin,
                builder: (context, child) => Transform.rotate(
                  // Eased, not linear. A constant-speed spinner is the
                  // mechanical thing; this leans into the turn and settles out
                  // of it, like something being wound.
                  angle:
                      Curves.easeInOutCubic.transform(spin.value) * math.pi * 2,
                  child: child,
                ),
                child:
                    Icon(OmIcons.byName('refresh'), size: 17, color: c.primary),
              ),
              const SizedBox(width: 8),
              Text(
                busy ? 'refreshing' : 'refresh memory',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: c.primary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Two soft rings of colour, turning at different rates around the orb.
///
/// Deliberately not a ring of even thickness: each is an arc whose alpha falls
/// away at both ends, so what you see is a smear of light travelling around
/// rather than a circle rotating. During a reload a third, brighter sweep runs
/// once around, which is the thing that says "working" without a spinner.
class _AuroraPainter extends CustomPainter {
  _AuroraPainter({
    required this.t,
    required this.pulse,
    required this.busy,
    required this.primary,
    required this.accent,
    required this.flow,
  });

  /// 0..1, wrapping. The idle drift.
  final double t;

  /// 0..1, one reload turn.
  final double pulse;
  final bool busy;
  final Color primary;
  final Color accent;
  final Color flow;

  void _arc(Canvas canvas, Rect rect, double start, double sweep, Color colour,
      double width) {
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = width
        ..shader = SweepGradient(
          startAngle: start,
          endAngle: start + sweep,
          colors: [
            colour.withValues(alpha: 0),
            colour,
            colour.withValues(alpha: 0),
          ],
          stops: const [0, 0.5, 1],
          transform: GradientRotation(start),
        ).createShader(rect)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.55),
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    const tau = math.pi * 2;

    // Everything rides OUTSIDE the orb. The orb is 124 across and this box is
    // 176 tall, so anything inside about 0.36 of the height is simply hidden
    // behind it, which is where the first version put both rings.
    // Outer ring, slow, brand purple.
    _arc(
      canvas,
      Rect.fromCircle(center: centre, radius: size.height * 0.485),
      t * tau,
      math.pi * 0.85,
      primary.withValues(alpha: 0.34),
      8,
    );

    // Inner ring, faster and the other way, coral. Counter-rotation is what
    // stops the pair reading as one object spinning.
    _arc(
      canvas,
      Rect.fromCircle(center: centre, radius: size.height * 0.445),
      -t * tau * 1.7 + math.pi,
      math.pi * 0.55,
      accent.withValues(alpha: 0.30),
      6,
    );

    // A third, very slow and very faint, at a third speed again. It is the
    // reason the pattern does not visibly loop: three periods that share no
    // common multiple you would notice inside a minute.
    _arc(
      canvas,
      Rect.fromCircle(center: centre, radius: size.height * 0.52),
      t * tau * 0.43 + math.pi * 0.7,
      math.pi * 1.1,
      flow.withValues(alpha: 0.16),
      9,
    );

    // The reload sweep: one bright pass, tight and quick, riding just outside
    // the orb.
    if (busy || pulse > 0) {
      final p = Curves.easeInOutCubic.transform(pulse);
      _arc(
        canvas,
        Rect.fromCircle(center: centre, radius: size.height * 0.44),
        p * tau - math.pi / 2,
        math.pi * 0.3,
        Color.lerp(flow, Colors.white, 0.4)!
            .withValues(alpha: 0.9 * (1 - (pulse - 0.5).abs() * 0.6)),
        6,
      );
    }
  }

  @override
  bool shouldRepaint(_AuroraPainter old) =>
      old.t != t || old.pulse != pulse || old.busy != busy;
}
