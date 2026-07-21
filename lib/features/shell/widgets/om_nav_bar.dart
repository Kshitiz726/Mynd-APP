import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/nav_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';

/// The floating bottom navigation bar - a liquid-glass capsule.
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
    required this.onCreate,
    this.alertsUnread = 0,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  /// Opens the create sheet: start a focus session, or talk to the coach.
  final VoidCallback onCreate;

  /// Unread follow-requests + comment alerts - drives the red dot on the bell.
  final int alertsUnread;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final dark = context.isDark;

    // IMPORTANT: a plain Container/Material - NOT a BottomAppBar (its clipper
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
            // Heavier blur over a thinner fill: the bar should look like frosted
            // glass laid on the page, not a light-grey slab drawn over it.
            blur: 44,
            opacity: dark ? 0.26 : 0.42,
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
                height: 60,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const tabs = AppTab.values;
                      // Five slots: the four destinations, with (+) sitting in
                      // the middle where the thumb naturally rests.
                      final slot = constraints.maxWidth / (tabs.length + 1);
                      final rawIndex = tabs.indexOf(current);
                      // Destinations after the centre button shift one slot right.
                      final index = rawIndex >= 2 ? rawIndex + 1 : rawIndex;

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
                              for (var i = 0; i < tabs.length; i++) ...[
                                if (i == 2)
                                  SizedBox(width: slot, child: _CreateButton(onTap: onCreate)),
                                SizedBox(
                                  width: slot,
                                  child: _NavItem(
                                    tab: tabs[i],
                                    active: tabs[i] == current,
                                    showDot: false,
                                    onTap: () {
                                      if (tabs[i] != current) Haptics.select();
                                      onSelect(tabs[i]);
                                    },
                                  ),
                                ),
                              ],
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

/// The centre (+): starts something rather than navigating somewhere, so it is
/// a solid, raised affordance instead of another flat destination.
class _CreateButton extends StatelessWidget {
  const _CreateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Center(
      child: OmTappable(
        onTap: () {
          Haptics.medium();
          onTap();
        },
        feedback: OmTapFeedback.none,
        pressedScale: 0.88,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: c.brandGradient,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.42),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 26),
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
          // A whisper of brand in the puck, so the lens belongs to the app
          // rather than being a neutral white pill.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: dark
                ? [
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.08),
                  ]
                : [
                    Colors.white.withValues(alpha: 0.92),
                    Color.lerp(Colors.white, c.primary, 0.10)!.withValues(alpha: 0.86),
                  ],
          ),
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
      child: Center(
        child: _NavIcon(tab: tab, color: color, active: active, showDot: showDot),
      ),
    );
  }
}

class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.tab,
    required this.color,
    required this.active,
    required this.showDot,
  });

  final AppTab tab;
  final Color color;
  final bool active;
  final bool showDot;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Outline and solid are cross-faded on top of each other rather than
        // swapped, so the glyph fills in instead of popping. Without labels the
        // icon carries the destination alone, so it is large and the active one
        // grows a touch further.
        TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          tween: Tween(end: active ? 1.0 : 0.0),
          builder: (context, t, _) => TweenAnimationBuilder<Color?>(
            duration: const Duration(milliseconds: 240),
            tween: ColorTween(end: color),
            builder: (context, value, _) => Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: Icon(tab.icon, color: value, size: 25),
                ),
                Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: Icon(tab.activeIcon, color: value, size: 26 + (t * 2)),
                ),
              ],
            ),
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
