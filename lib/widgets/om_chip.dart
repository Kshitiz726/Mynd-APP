import 'package:flutter/material.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import 'om_tappable.dart';

/// A small selectable chip (filters, tabs). Mirrors the prototype's `.fchip`.
class OmChip extends StatelessWidget {
  const OmChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          // The brand indigo, not c.primary. c.primary is the *light*
          // periwinkle in dark mode, so a selected chip was a pale fill with
          // a white label on it at 2.40:1 - the backlog filter you had just
          // picked was the one you could no longer read. brandSolid is the
          // deep end in both themes, and it matches the selected length tiles
          // and the coach's bubbles.
          color: selected ? c.brandSolid : c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.chip),
          border: Border.all(
            color: selected ? c.brandSolid : c.border.withValues(alpha: 0.6),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: c.primary
                        .withValues(alpha: context.isDark ? 0.14 : 0.28),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 15,
                  color: selected ? OmColors.onFill(c.brandSolid) : c.text2),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: selected ? OmColors.onFill(c.brandSolid) : c.text,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                    height: 1.3,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
