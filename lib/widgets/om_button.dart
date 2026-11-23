import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';
import 'om_tappable.dart' show softPress;

enum OmButtonVariant { accent, primary, soft, ghost }

/// The single button used across OurMynd. Replaces the prototype's
/// `.btn / .btn-accent / .btn-primary / .btn-soft / .btn-ghost` classes.
///
/// - Full-width by default (large, easy touch targets).
/// - Subtle press-scale micro-interaction, suppressed under reduce-motion.
class OmButton extends StatefulWidget {
  const OmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = OmButtonVariant.accent,
    this.icon,
    this.expand = true,
    this.color,
  });

  final String label;
  final VoidCallback? onPressed;
  final OmButtonVariant variant;
  final IconData? icon;
  final bool expand;

  /// Optional text/content color override (used by e.g. the "upgrade" button).
  final Color? color;

  @override
  State<OmButton> createState() => _OmButtonState();
}

class _OmButtonState extends State<OmButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final reduceMotion = context.select<SettingsProvider, bool>((s) => s.reduceMotion);
    final enabled = widget.onPressed != null;

    final (Color bg, Color fg, Gradient? gradient, List<BoxShadow> shadow, BoxBorder? border) =
        switch (widget.variant) {
      // Ink on the orange, not white. White on this peach measures 2.04:1 in
      // light and 1.88:1 in dark - the least readable thing in the app, on its
      // most-pressed button ("start pomodoro"). Ink on the same fill is 8.99:1
      // and 9.76:1, and reads the way a warm button is meant to.
      //
      // The halo is also cut in the dark. A 22px blur of saturated orange at
      // 0.42 over a near-black page is not a shadow, it is a glow, and it is
      // exactly the "too much gradient" the dark theme kept being accused of.
      OmButtonVariant.accent => (
          c.accent,
          OmColors.onFill(c.accent),
          null,
          [BoxShadow(color: c.accent.withValues(alpha: context.isDark ? 0.20 : 0.42), blurRadius: 22, spreadRadius: -2, offset: const Offset(0, 10))],
          null,
        ),
      // The premium CTA: brand gradient + a soft indigo glow.
      OmButtonVariant.primary => (
          c.primary,
          Colors.white,
          c.brandGradient,
          [BoxShadow(color: c.primary.withValues(alpha: context.isDark ? 0.18 : 0.40), blurRadius: 24, spreadRadius: -2, offset: const Offset(0, 12))],
          null,
        ),
      OmButtonVariant.soft => (
          c.surface,
          c.text,
          null,
          [BoxShadow(color: c.shadow.withValues(alpha: context.isDark ? 0.35 : 0.08), blurRadius: 16, spreadRadius: -4, offset: const Offset(0, 6))],
          Border.all(color: c.border, width: 1),
        ),
      OmButtonVariant.ghost => (Colors.transparent, c.text2, null, const <BoxShadow>[], null),
    };

    // The same cushioned press as OmTappable, which this widget does not go
    // through. Slow enough in that it reads as give rather than a click, and
    // settling on the way out without overshooting back past rest.
    final child = AnimatedScale(
      scale: _pressed ? softPress(0.97) : 1,
      duration: reduceMotion
          ? Duration.zero
          : Duration(milliseconds: _pressed ? 140 : 320),
      curve: _pressed ? Curves.easeOutSine : Curves.easeOutCubic,
      child: Container(
        width: widget.expand ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          color: gradient == null ? bg : null,
          gradient: gradient,
          border: border,
          borderRadius: BorderRadius.circular(AppRadius.control),
          boxShadow: enabled ? shadow : const [],
        ),
        child: Row(
          mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 18, color: widget.color ?? fg),
              const SizedBox(width: AppSpacing.sm),
            ],
            if (widget.expand)
              Flexible(
                child: Text(
                  widget.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: widget.color ?? fg,
                        fontWeight: widget.variant == OmButtonVariant.ghost ? FontWeight.w500 : FontWeight.w600,
                      ),
                ),
              )
            else
              Text(
                widget.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: widget.color ?? fg,
                      fontWeight: widget.variant == OmButtonVariant.ghost ? FontWeight.w500 : FontWeight.w600,
                    ),
              ),
          ],
        ),
      ),
    );

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: child,
      ),
    );
  }
}
