import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/nav_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_mascot.dart';
import '../../../widgets/om_tappable.dart';

/// The floating, pill-shaped bottom navigation bar.
///
/// A rounded, iOS-style frosted-glass capsule that floats above the bottom edge
/// (content blurs through it). Destinations collapse to a bare icon when
/// inactive; the selected one expands into a tinted pill showing its icon +
/// label — the modern "expanding pill" pattern, which keeps six tabs legible
/// and uncluttered. The final "you" destination is the user's mascot avatar.
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
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: context.isDark ? 0.5 : 0.16),
                blurRadius: 30,
                spreadRadius: -2,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: OmGlass(
            borderRadius: 30,
            blur: 32,
            opacity: context.isDark ? 0.42 : 0.6,
            child: SizedBox(
              height: 64,
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
                          if (tab != current) Haptics.select();
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

    final leading = isYou
        ? _YouAvatar(active: active)
        : _NavIcon(tab: tab, active: active, color: color, showDot: showDot);

    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none, // bar fires its own select haptic
      pressedScale: 0.88,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(horizontal: active ? 12 : 8, vertical: 9),
        decoration: BoxDecoration(
          color: active ? c.primaryTint : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            // The label reveals only for the active tab, animating its width.
            ClipRect(
              child: AnimatedAlign(
                alignment: Alignment.centerLeft,
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                widthFactor: active ? 1 : 0,
                child: AnimatedOpacity(
                  opacity: active ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 7),
                    child: Text(
                      tab.label,
                      maxLines: 1,
                      softWrap: false,
                      overflow: TextOverflow.clip,
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                            color: c.primary,
                            fontSize: 12.5,
                            letterSpacing: -0.2,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
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
    return Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: ScaleTransition(scale: anim, child: child),
          ),
          child: Icon(
            tab.icon,
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
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: active ? c.primary : Colors.transparent,
          width: 2,
        ),
      ),
      child: const OmMascot(size: 24),
    );
  }
}
