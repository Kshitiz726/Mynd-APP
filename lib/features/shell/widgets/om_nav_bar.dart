import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/nav_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_mascot.dart';
import '../../../widgets/om_tappable.dart';

/// The floating bottom navigation bar — a liquid-glass capsule.
///
/// Every destination shows its icon over its label; the selected one is marked
/// by a translucent "lens" that glides between slots rather than appearing in
/// place, which is what makes the movement read as liquid. Slots are equal
/// width, so the lens travel is linear and the longest label ("community")
/// cannot push its neighbours around.
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
    final dark = context.isDark;

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
                color: c.shadow.withValues(alpha: dark ? 0.55 : 0.18),
                blurRadius: 34,
                spreadRadius: -4,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: OmGlass(
            borderRadius: 28,
            blur: 36,
            opacity: dark ? 0.34 : 0.55,
            child: DecoratedBox(
              // Real glass is lit from above: a top-down sheen sells the depth
              // that blur alone cannot.
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: dark ? 0.10 : 0.45),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.55],
                ),
              ),
              child: SizedBox(
                height: 66,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const tabs = AppTab.values;
                      final slot = constraints.maxWidth / tabs.length;
                      final index = tabs.indexOf(current);

                      return Stack(
                        children: [
                          // The lens glides to the active slot behind the icons.
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutCubic,
                            left: slot * index,
                            top: 0,
                            bottom: 0,
                            width: slot,
                            child: _Lens(dark: dark),
                          ),
                          Row(
                            children: [
                              for (final tab in tabs)
                                SizedBox(
                                  width: slot,
                                  child: _NavItem(
                                    tab: tab,
                                    active: tab == current,
                                    showDot: tab == AppTab.alerts && alertsUnread > 0,
                                    onTap: () {
                                      if (tab != current) Haptics.select();
                                      onSelect(tab);
                                    },
                                  ),
                                ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The translucent puck marking the selected destination.
class _Lens extends StatelessWidget {
  const _Lens({required this.dark});

  final bool dark;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(19),
          color: dark
              ? Colors.white.withValues(alpha: 0.13)
              : Colors.white.withValues(alpha: 0.78),
          // A brighter hairline than the bar's own edge, so the puck reads as a
          // separate pane of glass sitting on top rather than a painted shape.
          border: Border.all(
            color: dark
                ? Colors.white.withValues(alpha: 0.20)
                : c.primary.withValues(alpha: 0.14),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: dark ? 0.28 : 0.10),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
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

    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none, // bar fires its own select haptic
      pressedScale: 0.9,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          tab == AppTab.you
              ? _YouAvatar(active: active)
              : _NavIcon(tab: tab, color: color, showDot: showDot),
          const SizedBox(height: 3),
          // Labels never wrap or ellipsize: the slot is sized for the longest
          // one, and shrinking beats clipping if a translation runs long.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                style: Theme.of(context).textTheme.labelMedium!.copyWith(
                      color: color,
                      fontSize: 10,
                      letterSpacing: -0.1,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                child: Text(tab.label, maxLines: 1, softWrap: false),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.tab,
    required this.color,
    required this.showDot,
  });

  final AppTab tab;
  final Color color;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Colour animates rather than the glyph swapping, so the icon never
        // pops between states.
        TweenAnimationBuilder<Color?>(
          duration: const Duration(milliseconds: 240),
          tween: ColorTween(end: color),
          builder: (context, value, _) => Icon(tab.icon, color: value, size: 21),
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
      child: const OmMascot(size: 18),
    );
  }
}
