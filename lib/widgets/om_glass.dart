import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';

/// A reusable iOS-style frosted-glass surface.
///
/// Lays a real gaussian backdrop blur behind a translucent fill with a soft
/// hairline highlight - the "vibrancy" look used by floating chrome (the bottom
/// nav, sticky headers, sheets). Content scrolling underneath blurs through it.
///
/// Three things separate glass that reads as glass from a translucent grey box,
/// and all three are here:
///
///  - **Saturation.** Real frosted glass concentrates the colour behind it. A
///    plain blur averages colour towards grey, which is why blur-only surfaces
///    look like fog. The backdrop filter boosts saturation as well as blurring.
///  - **A lit rim.** Light catches the top-left edge of a physical pane. Without
///    it the surface has no thickness and reads as paint.
///  - **Two shadows**, not one: a wide ambient that separates the pane from the
///    page, and a tight key that says it is floating above it.
///
/// Glass also only reads as glass when there is something behind it worth
/// blurring - put it over the brand gradient or content, never over a flat fill.
class OmGlass extends StatelessWidget {
  const OmGlass({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 22,
    this.opacity,
    this.border = true,
    this.padding,
    this.tint,
    this.elevated = false,
    this.sheen = true,
  });

  final Widget child;
  final double borderRadius;
  final double blur;

  /// Fill opacity of the frost. Defaults to a theme-aware value.
  final double? opacity;
  final bool border;
  final EdgeInsetsGeometry? padding;

  /// Brand colour washed through the frost. Defaults to the surface colour,
  /// which is the neutral chrome look; pass a brand colour for a surface that
  /// should feel like part of the page rather than floating over it.
  final Color? tint;

  /// Adds the layered drop shadow. Off by default because the blur is clipped,
  /// so a shadow has to be drawn by an outer box - several callers already wrap
  /// this widget in their own shadowed container and would otherwise get two.
  final bool elevated;

  /// The lit top-left rim. Worth turning off only for surfaces that meet
  /// another surface flush, where the highlight would read as a seam.
  final bool sheen;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final dark = context.isDark;
    final radius = BorderRadius.circular(borderRadius);
    final fill = opacity ?? (dark ? 0.58 : 0.72);
    // Low-stim mode flattens the UI everywhere else; glass is the loudest
    // surface treatment in the app, so it flattens hardest here.
    final lowStim = context.select<SettingsProvider, bool>((s) => s.lowStim);

    Widget pane = ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        // The saturation boost is a light-mode trick. Frosted glass over a
        // bright, busy page looks washed out without it, so the colours behind
        // get pushed back up. Over a near-black page there is almost nothing
        // to wash out, and the same boost instead takes the few saturated
        // pixels that are there - a brand bubble, an accent dot - and smears
        // them across the pane as coloured drift. Plain blur in dark.
        filter: lowStim || dark
            ? ImageFilter.blur(sigmaX: blur, sigmaY: blur)
            : ImageFilter.compose(
                outer: const ColorFilter.matrix(_saturate150),
                inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              ),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: (tint ?? c.surface).withValues(alpha: fill),
            borderRadius: radius,
            border: border
                ? Border.all(
                    color: Colors.white.withValues(alpha: dark ? 0.10 : 0.55),
                    width: 1,
                  )
                : null,
          ),
          child: Stack(
            children: [
              if (sheen && !lowStim && !dark)
                // The lit edge. A diagonal wash that dies out well before the
                // middle, so it is an edge catching light rather than a
                // gradient across the whole pane.
                //
                // Off in dark. The effect is a surface catching light from
                // somewhere, which is a thing that happens on a lit page; on a
                // dark one there is no light for it to catch, so a white
                // diagonal over every card reads as a gradient somebody added
                // for the sake of it. Dark surfaces separate by their own fill
                // and a hairline border instead, which is how dark interfaces
                // that look deliberate do it.
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: radius,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withValues(alpha: dark ? 0.10 : 0.28),
                            Colors.white.withValues(alpha: 0),
                          ],
                          stops: const [0.0, 0.42],
                        ),
                      ),
                    ),
                  ),
                ),
              child,
            ],
          ),
        ),
      ),
    );

    if (!elevated || lowStim) return pane;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          // Ambient: wide and very soft, lifts the pane off the page.
          BoxShadow(
            color: c.shadow.withValues(alpha: dark ? 0.42 : 0.10),
            blurRadius: 32,
            spreadRadius: -8,
            offset: const Offset(0, 16),
          ),
          // Key: tight, gives the bottom edge a contact shadow.
          BoxShadow(
            color: c.shadow.withValues(alpha: dark ? 0.28 : 0.06),
            blurRadius: 10,
            spreadRadius: -4,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: pane,
    );
  }
}

/// Luminance-preserving saturation boost to 150%, as a 4x5 colour matrix.
///
/// Built from the Rec.601 luma weights so brightening the colour does not also
/// change how light or dark the surface reads.
const List<double> _saturate150 = <double>[
  1.3935, -0.3575, -0.0360, 0, 0, //
  -0.1065, 1.1425, -0.0360, 0, 0, //
  -0.1065, -0.3575, 1.4640, 0, 0, //
  0, 0, 0, 1, 0, //
];
