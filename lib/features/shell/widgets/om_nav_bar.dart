import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../providers/nav_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';

/// The floating bottom navigation bar - a liquid-glass capsule.
///
/// Four destinations either side of a centre (+), the selected one marked by a
/// translucent "lens" that glides between slots rather than appearing in place,
/// which is what makes the movement read as liquid.
///
/// The centre used to be a fifth destination and was taken out, correctly:
/// focus and the coach are places you go, and a place you go belongs in a tab.
/// This (+) is not a destination. It is the app's one "put something in" verb -
/// a brain dump or a new goal - which is exactly the sort of thing that should
/// be reachable from every screen and owned by no screen. It sits in the middle
/// because that is the easiest point on the bar to hit with either thumb, and
/// the lens skips over it, because there is nothing there to select.
class OmNavBar extends StatelessWidget {
  const OmNavBar({
    super.key,
    required this.current,
    required this.onSelect,
    this.onAdd,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  /// Opens the add sheet. Null leaves the middle as plain glass, which is what
  /// the coach's sign-in gate wants: there is nothing to add to yet.
  final VoidCallback? onAdd;

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
                // Tall enough that the bar reads as a substantial pane of glass
                // rather than a thin strip, and that the centre button has room
                // to sit inside it instead of hanging off the top edge - the
                // glass clips its own blur, so anything overflowing is cut off.
                height: 72,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      const tabs = AppTab.values;
                      // Five slots: two tabs, the (+), two tabs. The centre one
                      // is not a destination, so a tab's slot is its own index
                      // shifted past the middle once it is on the right of it.
                      final centre = tabs.length ~/ 2;
                      final slot = constraints.maxWidth / (tabs.length + 1);
                      int slotOf(int i) => i < centre ? i : i + 1;

                      return Stack(
                        children: [
                          // The lens glides to the active slot behind the icons.
                          AnimatedPositioned(
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutCubic,
                            left: slot * slotOf(tabs.indexOf(current)),
                            top: 0,
                            bottom: 0,
                            width: slot,
                            child: _Lens(dark: dark),
                          ),
                          Row(
                            children: [
                              for (var i = 0; i < tabs.length; i++) ...[
                                if (i == centre)
                                  SizedBox(
                                    width: slot,
                                    child: _AddButton(onTap: onAdd),
                                  ),
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

/// The (+) in the middle of the bar.
///
/// Quiet on purpose. The first version was a two-hue gradient with a specular
/// highlight and a coloured glow, which is the language of a floating action
/// button on somebody else's app: it out-shouted every other thing on a bar
/// whose whole idea is restraint, and it made the middle of the screen the
/// loudest point in the interface.
///
/// One flat brand colour, one soft shadow. It is still the only filled shape on
/// the bar, which is all the prominence a single accent needs when everything
/// around it is frosted glass.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    if (onTap == null) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: 'add something',
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none, // the sheet fires its own
        pressedScale: 0.9,
        child: Center(
          child: Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.primary,
              boxShadow: [
                // Depth, not glow: the same soft drop the lens carries, in the
                // page's shadow colour rather than in brand purple.
                BoxShadow(
                  color: c.shadow.withValues(
                    alpha: context.isDark ? 0.34 : 0.16,
                  ),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(OmIcons.byName('plus'), color: Colors.white, size: 23),
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

  /// One glyph, resting (outline) or selected (filled).
  ///
  /// Chat is special-cased: Material has no *circular* filled speech bubble, so
  /// its resting Lucide circle used to fill into a square `chat_bubble` and the
  /// shape jumped. Here both states are the same hand-drawn round bubble, so
  /// selecting it only fills the shape in rather than changing it.
  Widget _glyph({required bool filled, required Color color, required double size}) {
    if (tab == AppTab.coach) {
      return _ChatCircleGlyph(color: color, filled: filled, size: size);
    }
    return Icon(filled ? tab.activeIcon : tab.icon, color: color, size: size);
  }

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
            builder: (context, value, _) {
            final col = value ?? color;
            return Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: (1 - t).clamp(0.0, 1.0),
                  child: _glyph(filled: false, color: col, size: 27),
                ),
                Opacity(
                  opacity: t.clamp(0.0, 1.0),
                  child: _glyph(filled: true, color: col, size: 28 + (t * 2)),
                ),
              ],
            );
          },
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

/// A round speech bubble - a circle with a small tail at the lower-left, in the
/// spirit of Lucide's `messageCircle`. Drawn by hand so the *same* shape can be
/// an outline (resting) or a solid fill (selected), which the Material icon set
/// cannot offer for a circular bubble.
class _ChatCircleGlyph extends StatelessWidget {
  const _ChatCircleGlyph({
    required this.color,
    required this.filled,
    required this.size,
  });

  final Color color;
  final bool filled;
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _ChatCirclePainter(color: color, filled: filled),
    );
  }
}

class _ChatCirclePainter extends CustomPainter {
  _ChatCirclePainter({required this.color, required this.filled});

  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final stroke = s * 0.085;
    // A plump circle sitting up and to the right, with a short stubby tail
    // dropping to the lower-left, in the spirit of the iMessage bubble.
    final r = s * 0.38;
    final centre = Offset(s * 0.53, s * 0.44);

    final bubble = Path()
      ..addOval(Rect.fromCircle(center: centre, radius: r));
    final tail = Path()
      ..moveTo(centre.dx - r * 0.66, centre.dy + r * 0.36)
      ..lineTo(centre.dx - r * 1.02, centre.dy + r * 1.02)
      ..lineTo(centre.dx - r * 0.20, centre.dy + r * 0.72)
      ..close();
    final glyph = Path.combine(PathOperation.union, bubble, tail);

    final paint = Paint()
      ..color = color
      ..isAntiAlias = true
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    if (filled) {
      canvas.drawPath(glyph, paint..style = PaintingStyle.fill);
    } else {
      canvas.drawPath(
        glyph,
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(_ChatCirclePainter old) =>
      old.color != color || old.filled != filled;
}
