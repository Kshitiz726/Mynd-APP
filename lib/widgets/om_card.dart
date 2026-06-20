import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';
import 'om_tappable.dart';

/// The standard rounded surface used everywhere. In low-stimulation mode the
/// shadow is removed (matching the prototype's `.low-stim .card{box-shadow:none}`)
/// so the UI flattens and calms down.
class OmCard extends StatelessWidget {
  const OmCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color,
    this.radius = AppRadius.card,
    this.border,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;
  final BoxBorder? border;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final lowStim = context.select<SettingsProvider, bool>((s) => s.lowStim);

    final dark = context.isDark;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: BorderRadius.circular(radius),
        // Hairline border keeps soft cards crisp against the warm background.
        border: border ?? Border.all(color: c.border.withValues(alpha: dark ? 0.6 : 0.9), width: 1),
        boxShadow: lowStim
            ? const []
            : [
                // Ambient (wide, very soft) + key (tight, lifts the card).
                BoxShadow(
                  color: c.shadow.withValues(alpha: dark ? 0.45 : 0.08),
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

    if (onTap == null) return card;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      pressedScale: 0.98,
      child: card,
    );
  }
}
