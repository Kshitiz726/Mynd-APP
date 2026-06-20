import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/nav_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_mascot.dart';
import '../../../widgets/om_tappable.dart';

/// The floating, pill-shaped bottom navigation bar.
///
/// Styled after the reference: a rounded, iOS-style frosted-glass capsule that
/// floats above the bottom edge (content blurs through it), each destination an
/// icon + label, the active one filled and lit inside a tinted chip
/// (Facebook-style fill). The final "you" destination is rendered as the user's
/// circular mascot avatar.
class OmNavBar extends StatelessWidget {
  const OmNavBar({
    super.key,
    required this.current,
    required this.onSelect,
    this.alertsUnread = 0,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  /// Unread follow-requests + comment alerts — drives the red dot on the bell.
  final int alertsUnread;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // IMPORTANT: a plain Container/Material — NOT a BottomAppBar (its clipper
    // reads ScaffoldGeometry during hit-test and freezes input on desktop).
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
        // Shadow lives on this outer (unclipped) box; the glass clips its blur.
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: context.isDark ? 0.5 : 0.16),
                blurRadius: 28,
                spreadRadius: -2,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: OmGlass(
            borderRadius: 28,
            blur: 30,
            opacity: context.isDark ? 0.1 : 0.25,
            child: SizedBox(
              height: 66,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final tab in AppTab.values)
                      _NavItem(
                        tab: tab,
                        active: tab == current,
                        showDot: tab == AppTab.alerts && alertsUnread > 0,
                        onTap: () {
                          Haptics.select();
                          onSelect(tab);
                        },
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.active,
    required this.onTap,
    this.showDot = false,
  });

  final AppTab tab;
  final bool active;
  final bool showDot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final color = active ? c.primary : c.text2;
    final isYou = tab == AppTab.you;

    return Expanded(
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none, // bar fires its own select haptic
        pressedScale: 0.9,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isYou)
                _YouAvatar(active: active)
              else
                _IconChip(tab: tab, active: active, color: color, showDot: showDot),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 200),
                style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: color,
                      fontSize: 10,
                      letterSpacing: 0,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    ),
                child: Text(tab.label, maxLines: 1, overflow: TextOverflow.clip),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({
    required this.tab,
    required this.active,
    required this.color,
    required this.showDot,
  });

  final AppTab tab;
  final bool active;
  final Color color;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      padding: EdgeInsets.symmetric(horizontal: active ? 16 : 8, vertical: 4),
      decoration: BoxDecoration(
        color: active ? c.primaryTint : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: Icon(
              active ? tab.activeIcon : tab.icon,
              key: ValueKey(active),
              color: color,
              size: 22,
            ),
          ),
          if (showDot)
            Positioned(
              right: -3,
              top: -2,
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
    );
  }
}

/// The "you" destination — the user's mascot avatar, ringed when active.
class _YouAvatar extends StatelessWidget {
  const _YouAvatar({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? c.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: const OmMascot(size: 26),
    );
  }
}
