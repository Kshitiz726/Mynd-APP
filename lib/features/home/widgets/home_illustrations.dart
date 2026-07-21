import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';

/// The two empty states on Home, drawn rather than shipped as assets.
///
/// These are painters, not SVGs, for one reason that matters: they take their
/// colours from [OmColors] at paint time, so light and dark are one drawing
/// instead of two files that have to be kept in step - and there is no second
/// palette to drift out of sync with the theme. It also means no new
/// dependency and no asset to decode, which is worth something for artwork
/// that exists to be looked at for two seconds.
///
/// Both are deliberately quiet. An empty state on an ADHD app is a moment when
/// there is nothing to do, and that should read as permission rather than as a
/// gap where content failed to arrive.

/// "You're all caught up" - the do-this-now empty state.
///
/// A low sun over a horizon, in the app's own coral and lilac.
///
/// This was a green checkmark badge, which was wrong twice. Green is `success`
/// - a status colour, the one the app uses for "this worked" - so an empty
/// state was borrowing the vocabulary of a confirmation toast and reading as
/// off-brand next to a page washed in coral and lilac. And a tick says
/// "completed", which is a claim about work; there may be nothing here because
/// you finished, or because there was never anything. A sun says the softer
/// and truer thing: it is fine, stop looking.
///
/// The rays are uneven on purpose - evenly spaced spokes read as a loading
/// spinner, which is the one thing an empty state must not look like.
class AllCaughtUpArt extends StatelessWidget {
  const AllCaughtUpArt({super.key, this.message = "you're all caught up"});

  final String message;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Spans the section rather than floating as a small icon in a wide
          // empty box, which was the old shape of this.
          SizedBox(
            width: double.infinity,
            height: 116,
            child: CustomPaint(
              painter: _CaughtUpPainter(
                primary: c.primary,
                accent: c.accent,
                flow: c.flow,
                dark: context.isDark,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            'take a breather - nothing needs you right now.',
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: c.text2, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _CaughtUpPainter extends CustomPainter {
  _CaughtUpPainter({
    required this.primary,
    required this.accent,
    required this.flow,
    required this.dark,
  });

  final Color primary;
  final Color accent;
  final Color flow;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    // Sits high, so the horizon lines below have room and the whole thing
    // reads as a sun *over* something rather than a circle with a few dashes.
    final centre = Offset(size.width / 2, size.height * 0.40);
    final r = size.height * 0.235;

    // Ground glow, so the badge sits in something rather than on nothing.
    canvas.drawCircle(
      centre,
      r * 2.6,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: dark ? 0.20 : 0.16),
            primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: centre, radius: r * 2.6)),
    );

    // The rays. Uneven lengths and gaps - a spinner has neither.
    //
    // Upper half only, and slightly past horizontal at each end: rays coming
    // off the bottom of a sun would run straight through the horizon lines
    // below it, and light does not fall that way anyway.
    const spokes = <double>[-3.02, -2.62, -2.18, -1.76, -1.36, -0.94, -0.50, -0.12];
    const lengths = <double>[0.34, 0.52, 0.36, 0.50, 0.32, 0.48, 0.34, 0.44];
    for (var i = 0; i < spokes.length; i++) {
      final a = spokes[i];
      final inner = r * 1.42;
      final outer = inner + r * lengths[i];
      canvas.drawLine(
        centre + Offset(math.cos(a), math.sin(a)) * inner,
        centre + Offset(math.cos(a), math.sin(a)) * outer,
        Paint()
          ..color = (i.isEven ? accent : primary)
              .withValues(alpha: dark ? 0.45 : 0.38)
          ..strokeWidth = 3.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // The sun. Coral into brand purple rather than a flat disc, so it belongs
    // to the same gradient the top of Home is painted in.
    canvas.drawCircle(
      centre,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(accent, Colors.white, dark ? 0.12 : 0.30)!,
            accent,
            Color.lerp(accent, primary, 0.45)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: centre, radius: r)),
    );
    // A lit top-left rim, the same idea as the glass surfaces.
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: r - 1.5),
      math.pi * 1.05,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: dark ? 0.35 : 0.55),
    );

    // The horizon: three lines, shortening and fading downwards so the eye
    // reads distance rather than a stack of dashes. The sun sits above them
    // rather than behind - "settled" rather than "setting", which is the
    // difference between a rest and an ending.
    const widths = <double>[0.62, 0.40, 0.22];
    const drops = <double>[0.74, 0.86, 0.96];
    for (var i = 0; i < widths.length; i++) {
      final y = size.height * drops[i];
      final half = size.width * widths[i] / 2;
      canvas.drawLine(
        Offset(centre.dx - half, y),
        Offset(centre.dx + half, y),
        Paint()
          ..color = (i == 1 ? flow : primary)
              .withValues(alpha: (dark ? 0.42 : 0.34) - i * 0.09)
          ..strokeWidth = 4.0 - i * 0.8
          ..strokeCap = StrokeCap.round,
      );
    }

    // Two drifting motes. Cheap, and they stop the composition being perfectly
    // symmetrical, which is what makes it feel drawn rather than generated.
    canvas.drawCircle(
      Offset(size.width * 0.24, size.height * 0.22),
      4,
      Paint()..color = accent.withValues(alpha: 0.50),
    );
    canvas.drawCircle(
      Offset(size.width * 0.78, size.height * 0.34),
      3,
      Paint()..color = primary.withValues(alpha: 0.42),
    );
  }

  @override
  bool shouldRepaint(_CaughtUpPainter old) =>
      old.primary != primary ||
      old.accent != accent ||
      old.flow != flow ||
      old.dark != dark;
}

/// "No active goals" - a target with an arrow already in it.
///
/// The arrow is landed rather than in flight: the invitation is to set a goal,
/// and a dart still travelling is a goal you might miss.
class NoGoalsArt extends StatelessWidget {
  const NoGoalsArt({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return SizedBox(
      width: double.infinity,
      height: 104,
      child: CustomPaint(
        painter: _NoGoalsPainter(
          primary: c.primary,
          accent: c.accent,
          flow: c.flow,
          dark: context.isDark,
        ),
      ),
    );
  }
}

class _NoGoalsPainter extends CustomPainter {
  _NoGoalsPainter({
    required this.primary,
    required this.accent,
    required this.flow,
    required this.dark,
  });

  final Color primary;
  final Color accent;
  final Color flow;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height * 0.52);
    final r = size.height * 0.38;

    canvas.drawCircle(
      centre,
      r * 2.2,
      Paint()
        ..shader = RadialGradient(
          colors: [
            primary.withValues(alpha: dark ? 0.18 : 0.14),
            primary.withValues(alpha: 0),
          ],
        ).createShader(Rect.fromCircle(center: centre, radius: r * 2.2)),
    );

    // Three rings, thinning outwards so the eye lands in the middle.
    for (var i = 0; i < 3; i++) {
      final rr = r * (1 - i * 0.30);
      canvas.drawCircle(
        centre,
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.0 - i * 0.4
          ..color = (i.isEven ? primary : flow)
              .withValues(alpha: dark ? 0.60 - i * 0.10 : 0.52 - i * 0.08),
      );
    }
    // The bullseye.
    canvas.drawCircle(centre, r * 0.16, Paint()..color = accent);

    // The arrow, landed, coming in from the upper right.
    final dir = Offset(math.cos(-2.5), math.sin(-2.5));
    final tail = centre - dir * r * 1.95;
    canvas.drawLine(
      tail,
      centre - dir * r * 0.10,
      Paint()
        ..color = accent
        ..strokeWidth = 3.4
        ..strokeCap = StrokeCap.round,
    );
    // Fletching: two short strokes across the tail.
    final perp = Offset(-dir.dy, dir.dx);
    for (final t in [0.0, 0.16]) {
      final at = tail + dir * (r * t);
      canvas.drawLine(
        at - perp * 7,
        at + perp * 7,
        Paint()
          ..color = accent.withValues(alpha: 0.75)
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_NoGoalsPainter old) =>
      old.primary != primary ||
      old.accent != accent ||
      old.flow != flow ||
      old.dark != dark;
}
