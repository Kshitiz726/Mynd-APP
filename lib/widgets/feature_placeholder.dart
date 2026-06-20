import 'package:flutter/material.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/om_icons.dart';

/// A clean, on-brand placeholder used for screens that are scaffolded but whose
/// full build lands in a later pass. Keeps the app navigable and visually
/// coherent instead of throwing "route not found".
class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    super.key,
    required this.title,
    required this.subtitle,
    required this.iconName,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final String iconName;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final body = Padding(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showBack)
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(OmIcons.byName('chevL'), color: c.text),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                  child: Icon(OmIcons.byName(iconName), size: 30, color: c.text2),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('coming together', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  "this part of OurMynd is being built\nin the next pass.",
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return showBack ? Scaffold(body: SafeArea(child: body)) : SafeArea(child: body);
  }
}
