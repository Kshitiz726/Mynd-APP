import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';
import 'om_tappable.dart';

/// The standard rounded surface used everywhere. In low-stimulation mode the
/// shadow is removed (matching the prototype's `.low-stim .card{box-shadow:none}`)
/// so the UI flattens and calms down.
///
/// Deliberately blur-free: the premium "frosted" hero look is faked with a
/// [gradient] tint + a light highlight [border] instead of a live
/// [BackdropFilter], so a screen full of these cards still scrolls at 120fps.
/// Use [OmCard.hero] for the tinted, glowing feature cards.
class OmCard extends StatelessWidget {
  const OmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.gradient,
    this.radius = AppRadius.card,
    this.border,
    this.glowColor,
    this.onTap,
    this.onLongPress,
    this.pressedScale = 0.98,
  });

  /// A tinted, softly-glowing feature card — the premium look the dashboard's
  /// hero surfaces used to get from stacked blurs, now cheap. [tint] colours a
  /// subtle top-left→bottom-right wash and the matching border + glow.
  factory OmCard.hero({
    Key? key,
    required Widget child,
    required Color tint,
    EdgeInsetsGeometry padding = const EdgeInsets.all(18),
    double radius = AppRadius.card,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return OmCard(
      key: key,
      padding: padding,
      radius: radius,
      onTap: onTap,
      onLongPress: onLongPress,
      glowColor: tint,
      border: Border.all(color: tint.withValues(alpha: 0.28), width: 1.5),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [tint.withValues(alpha: 0.16), tint.withValues(alpha: 0.04)],
      ),
      child: child,
    );
  }

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  /// Optional fill gradient (overrides [color]) — used by hero/feature cards.
  final Gradient? gradient;
  final double radius;
  final BoxBorder? border;

  /// Optional accent colour for a soft coloured drop-shadow (feature cards).
  final Color? glowColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double pressedScale;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final lowStim = context.select<SettingsProvider, bool>((s) => s.lowStim);

    final dark = context.isDark;
    final glow = glowColor;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? c.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        // Hairline border keeps soft cards crisp against the warm background.
        border: border ?? Border.all(color: c.border.withValues(alpha: dark ? 0.6 : 0.9), width: 1),
        boxShadow: lowStim
            ? const []
            : [
                // Ambient (wide, very soft) + key (tight, lifts the card).
                BoxShadow(
                  color: (glow ?? c.shadow).withValues(alpha: dark ? 0.45 : (glow != null ? 0.16 : 0.08)),
                  blurRadius: 32,
                  spreadRadius: -6,
                  offset: const Offset(0, 18),
                ),
                BoxShadow(
                  color: c.shadow.withValues(alpha: dark ? 0.30 : 0.05),
                  blurRadius: 10,
                  spreadRadius: -4,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: child,
    );

    if (onTap == null && onLongPress == null) return card;
    return OmTappable(
      onTap: onTap,
      onLongPress: onLongPress,
      feedback: OmTapFeedback.light,
      pressedScale: pressedScale,
      child: card,
    );
  }
}
