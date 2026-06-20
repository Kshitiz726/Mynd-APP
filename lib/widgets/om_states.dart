import 'package:flutter/material.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/om_icons.dart';
import 'om_tappable.dart';

/// Lowercase section label ("habits & routines"), optionally with a trailing
/// action (e.g. "view all"). Mirrors `h2.sec`.
class OmSectionHeader extends StatelessWidget {
  const OmSectionHeader(this.title, {super.key, this.trailing, this.onTrailingTap});

  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, AppSpacing.xl, 4, AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: c.text2,
                  ),
            ),
          ),
          if (trailing != null)
            OmTappable(
              onTap: onTrailingTap,
              pressedScale: 0.93,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: c.surfaceAlt,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  trailing!,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.text2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Gentle empty state. The copy is intentionally warm and low-pressure.
class OmEmptyState extends StatelessWidget {
  const OmEmptyState({super.key, required this.message, this.icon});

  final String message;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      c.primary.withValues(alpha: 0.15),
                      c.primary.withValues(alpha: 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(color: c.primary.withValues(alpha: 0.1)),
                ),
                child: Center(
                  child: Icon(OmIcons.byName(icon!), size: 36, color: c.primary.withValues(alpha: 0.8)),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            Text(
              message.toLowerCase(),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: c.text2,
                    height: 1.5,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A shimmering placeholder block for loading/skeleton states.
class OmSkeleton extends StatefulWidget {
  const OmSkeleton({super.key, this.height = 16, this.width, this.radius = 10});

  final double height;
  final double? width;
  final double radius;

  @override
  State<OmSkeleton> createState() => _OmSkeletonState();
}

class _OmSkeletonState extends State<OmSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.4, end: 0.9).animate(_ctrl),
      child: Container(
        height: widget.height,
        width: widget.width,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}
