import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_durations.dart';
import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../providers/settings_provider.dart';

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
      OmButtonVariant.accent => (
          c.accent,
          Colors.white,
          null,
          [BoxShadow(color: c.accent.withValues(alpha: 0.42), blurRadius: 22, spreadRadius: -2, offset: const Offset(0, 10))],
          null,
        ),
      // The premium CTA: brand gradient + a soft indigo glow.
      OmButtonVariant.primary => (
          c.primary,
          Colors.white,
          c.brandGradient,
          [BoxShadow(color: c.primary.withValues(alpha: 0.40), blurRadius: 24, spreadRadius: -2, offset: const Offset(0, 12))],
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

    final child = AnimatedScale(
      scale: _pressed ? 0.97 : 1,
      duration: reduceMotion ? Duration.zero : AppDurations.fast,
      curve: Curves.easeOutCubic,
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
