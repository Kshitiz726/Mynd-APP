import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../widgets/om_tappable.dart';

class _PlanOption {
  const _PlanOption({
    required this.title,
    required this.price,
    this.subtitle,
    this.oldPrice,
    this.badge,
  });
  final String title;
  final String price;
  final String? subtitle;
  final String? oldPrice;
  final String? badge;
}

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  int _selectedIndex = 0;

  static const _options = [
    _PlanOption(
      title: 'Yearly',
      price: '£24.99/year',
      oldPrice: '£49.99/year',
      subtitle: 'Includes Family Sharing',
      badge: 'For You 50% OFF',
    ),
    _PlanOption(
      title: 'Monthly',
      price: '£7.99/month',
    ),
    _PlanOption(
      title: 'Lifetime',
      price: '£139.99',
      subtitle: 'Pay Once, Use Forever\nIncludes Family Sharing',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final selectedOption = _options[_selectedIndex];

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Header with close button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OmTappable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Icon(OmIcons.byName('close'), color: c.text2, size: 24),
                  ),
                ],
              ),
            ),
            
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                children: [
                  // Title
                  Text(
                    'OurMynd Premium',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Features subtitle
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Unlimited AI coach, Full daily planning, Unlimited tasks + goals, AI memory system, WhatsApp + SMS reminders, Voice input, Calendar sync, Unlimited habits, Evening reflection.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: c.text2,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Plan Options
                  for (int i = 0; i < _options.length; i++) ...[
                    _PlanOptionCard(
                      option: _options[i],
                      isSelected: _selectedIndex == i,
                      onTap: () => setState(() => _selectedIndex = i),
                    ),
                    const SizedBox(height: 16),
                  ],

                  const SizedBox(height: 16),
                  Center(
                    child: OmTappable(
                      onTap: () => Toast.show(context, 'Purchases restored'),
                      child: Text(
                        'Restore Purchase',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: c.text2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
            
            // Bottom sticky area
            Container(
              padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 16, AppSpacing.screenH, AppSpacing.lg),
              decoration: BoxDecoration(
                color: c.bg, // Blend with background
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Price breakdown above button
                  if (selectedOption.oldPrice != null) ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          selectedOption.oldPrice!,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: c.text2,
                            decoration: TextDecoration.lineThrough,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${selectedOption.price} (50% OFF)',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                  ],
                  
                  // Continue Button
                  OmTappable(
                    onTap: () => Toast.show(context, 'Starting ${selectedOption.title}…'),
                    pressedScale: 0.98,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: c.primary,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'Continue',
                            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Cancel Anytime',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Back button
                  OmTappable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(OmIcons.byName('chevL'), size: 16, color: c.text2),
                        const SizedBox(width: 4),
                        Text(
                          'Back',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: c.text2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanOptionCard extends StatelessWidget {
  const _PlanOptionCard({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _PlanOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    
    final card = Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isSelected ? c.primary.withValues(alpha: 0.08) : c.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isSelected ? c.primary : Colors.transparent,
          width: 2,
        ),
        boxShadow: isSelected
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                )
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Radio circle
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 2, right: 16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? c.primary : Colors.transparent,
              border: Border.all(
                color: isSelected ? c.primary : c.text2.withValues(alpha: 0.3),
                width: 2,
              ),
            ),
            child: isSelected
                ? const Icon(Icons.check, size: 16, color: Colors.white)
                : null,
          ),
          
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  option.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
                if (option.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    option.subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: c.text2,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
          
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                option.price,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              if (option.oldPrice != null) ...[
                const SizedBox(height: 4),
                Text(
                  option.oldPrice!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: c.text2,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    if (option.badge == null) {
      return OmTappable(
        onTap: onTap,
        pressedScale: 0.98,
        child: card,
      );
    }

    return OmTappable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          card,
          Positioned(
            top: -12,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: c.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                option.badge!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
