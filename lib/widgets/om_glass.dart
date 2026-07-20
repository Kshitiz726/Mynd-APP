import 'dart:ui';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';

/// A reusable iOS-style frosted-glass surface.
///
/// Lays a real gaussian backdrop blur behind a translucent fill with a soft
/// hairline highlight - the "vibrancy" look used by floating chrome (the bottom
/// nav, sticky headers, sheets). Content scrolling underneath blurs through it.
///
/// Wrap it in a [Container] with a `boxShadow` if you want a drop shadow - the
/// blur is clipped, so the shadow must live on an outer (unclipped) box.
class OmGlass extends StatelessWidget {
  const OmGlass({
    super.key,
    required this.child,
    this.borderRadius = 24,
    this.blur = 22,
    this.opacity,
    this.border = true,
    this.padding,
  });

  final Widget child;
  final double borderRadius;
  final double blur;

  /// Fill opacity of the frost. Defaults to a theme-aware value.
  final double? opacity;
  final bool border;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final radius = BorderRadius.circular(borderRadius);
    final fill = opacity ?? (context.isDark ? 0.58 : 0.72);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: c.surface.withValues(alpha: fill),
            borderRadius: radius,
            border: border
                ? Border.all(
                    color: (context.isDark ? Colors.white : Colors.white)
                        .withValues(alpha: context.isDark ? 0.08 : 0.55),
                    width: 1,
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}
