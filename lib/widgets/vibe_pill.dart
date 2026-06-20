import 'package:flutter/material.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/om_icons.dart';
import '../models/energy_level.dart';
import 'om_tappable.dart';

/// The tappable "high energy ›" pill on Home. Color-codes to the current
/// [EnergyLevel] and opens the energy picker on tap.
class VibePill extends StatelessWidget {
  const VibePill({super.key, required this.energy, required this.onTap});

  final EnergyLevel energy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = energy.color(context);
    final label = '${energy.label} energy';

    return OmTappable(
      onTap: onTap,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: color.withValues(alpha: context.isDark ? 0.22 : 0.16),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.28)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(energy.icon, size: 15, color: color),
            const SizedBox(width: 7),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 4),
            Icon(OmIcons.byName('chevR'), size: 15, color: color),
          ],
        ),
      ),
    );
  }
}
