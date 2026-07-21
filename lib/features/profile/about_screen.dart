import 'dart:ui';
import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/om_icons.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_top_bar.dart';
import '../../widgets/om_tappable.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // Ambient mood lighting for glassy effect
          Align(
            alignment: const Alignment(-0.8, -0.6),
            child: _Glow(color: c.primary, size: 360),
          ),
          Align(
            alignment: const Alignment(0.8, 0.4),
            child: _Glow(color: c.accent, size: 420),
          ),
          
          SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenH,
                AppSpacing.screenTop,
                AppSpacing.screenH,
                AppSpacing.screenBottom,
              ),
              children: [
                // A chevron on the left, not a cross on the right: this is a
                // pushed page like any other, and dismissal should not have two
                // different shapes depending on which page you are on.
                const OmTopBar(title: 'about', leading: OmBackButton()),
                const SizedBox(height: AppSpacing.lg),
                
                const _AboutCard(title: 'App Version', subtitle: 'v1.0.0 (Build 42)', icon: 'smartphone'),
                const _AboutCard(title: 'Terms of Service', subtitle: 'Read our terms', icon: 'file-text', showArrow: true),
                const _AboutCard(title: 'Privacy Policy', subtitle: 'How we handle your data', icon: 'shield', showArrow: true),
                const _AboutCard(title: 'Open Source Licenses', subtitle: 'Libraries we use', icon: 'code', showArrow: true),
                
                const SizedBox(height: AppSpacing.xl * 2),
                Center(
                  child: Text(
                    'Crafted with ❤️ for ADHD brains',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.text2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: context.isDark ? 0.22 : 0.18),
              color.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.showArrow = false,
  });

  final String title;
  final String subtitle;
  final String icon;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: OmTappable(
        onTap: () {},
        pressedScale: 0.98,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: c.surface.withValues(alpha: context.isDark ? 0.4 : 0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: c.border.withValues(alpha: 0.5)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: c.primaryTint,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(OmIcons.byName(icon), color: c.primary, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2),
                        ),
                      ],
                    ),
                  ),
                  if (showArrow)
                    Icon(OmIcons.byName('chevR'), color: c.text2, size: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
