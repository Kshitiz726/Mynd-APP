import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/om_icons.dart';
import 'om_tappable.dart';

/// Standard header for pushed detail screens (Notebook, Alarms, Reminders,
/// Paywall): a circular back button on the top-left followed by a title +
/// subtitle - a single, consistent chrome across the whole app.
class OmScreenHeader extends StatelessWidget {
  const OmScreenHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.filledBack = false,
    this.onBack,
  });

  final String title;
  final String? subtitle;

  /// When true the back button is a solid primary circle with a white chevron
  /// (Alarms/Reminders); otherwise a soft white circle (Notebook).
  final bool filledBack;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        OmTappable(
          pressedScale: 0.88,
          onTap: onBack ?? () => Navigator.of(context).maybePop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: filledBack ? c.primary : c.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: filledBack
                      ? c.primary.withValues(alpha: 0.3)
                      : Colors.black.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Icon(CupertinoIcons.chevron_back,
                size: 24, color: filledBack ? Colors.white : c.text),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
