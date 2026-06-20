import 'package:flutter/material.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';

/// The single, standardized top bar used across every primary section
/// (Today, Focus, Community, Alerts, Coach, You).
///
/// Before this, each screen rolled its own header with different fonts, sizes
/// and spacing. [OmTopBar] gives them one consistent, professional chrome:
/// an optional [leading] (avatar / mascot), a title + optional subtitle, and a
/// trailing cluster of [actions]. Screens drop it in as the first item of their
/// scroll view so the rhythm matches everywhere.
class OmTopBar extends StatelessWidget {
  const OmTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
    this.titleWidget,
    this.dense = false,
  });

  /// The large section title (e.g. "focus", "community").
  final String title;

  /// Optional supporting line under the title.
  final String? subtitle;

  /// Optional leading widget shown before the title (avatar, mascot…).
  final Widget? leading;

  /// Right-aligned action widgets (icon buttons, pills, avatar…).
  final List<Widget> actions;

  /// When provided, replaces the default title/subtitle column entirely — lets a
  /// screen keep bespoke content (e.g. the coach's model picker) while still
  /// sharing the bar's height, spacing and action layout.
  final Widget? titleWidget;

  /// Tighter vertical padding for screens that sit flush under the status bar.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final c = context.omColors;

    return Padding(
      padding: EdgeInsets.only(bottom: dense ? AppSpacing.md : AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: titleWidget ??
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: t.headlineMedium?.copyWith(letterSpacing: -0.4),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: t.bodySmall?.copyWith(
                          fontWeight: FontWeight.w500,
                          color: c.text2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.sm),
                  actions[i],
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// A consistent circular icon action for the top bar (settings, close, search…).
/// Matches the soft-surface chrome used by [OmTopBar].
class OmTopBarAction extends StatelessWidget {
  const OmTopBarAction({
    super.key,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.showDot = false,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onTap;

  /// Solid primary circle with a white glyph (vs a soft surface circle).
  final bool filled;
  final bool showDot;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final button = Material(
      color: filled ? c.primary : c.surface,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 42,
          height: 42,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              Icon(icon, size: 20, color: filled ? Colors.white : c.text),
              if (showDot)
                Positioned(
                  right: 9,
                  top: 9,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: c.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final wrapped = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: (filled ? c.primary : c.shadow)
                .withValues(alpha: context.isDark ? 0.4 : 0.10),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: button,
    );

    return tooltip == null ? wrapped : Tooltip(message: tooltip!, child: wrapped);
  }
}
