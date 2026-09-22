import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/nav_provider.dart';
import '../../../widgets/om_tappable.dart';

/// The bottom navigation: a flat row of glyphs, and nothing else.
///
/// This used to be a floating frosted capsule with a shadow, a top-down sheen
/// and a translucent "lens" that glided between slots. It was the loudest thing
/// on every screen, which is the wrong job for navigation: the bar is how you
/// leave, not something to look at.
///
/// So the chrome is gone and the icons sit straight on the page. What marks the
/// current tab is the glyph going solid *and* taking the brand colour. Both,
/// not either: colour alone is easy to lose at a glance and is no signal at all
/// to anyone who cannot separate those two hues, and a fill in the text colour
/// reads as a smudge rather than as a selection. The flat redraw dropped the
/// brand tint by accident and left a near-black blob marking the current tab.
///
/// Five evenly spaced slots, the middle one being the (+). The (+) is not a
/// destination - it is the app's one "put something in" verb, which belongs
/// everywhere and to no screen - so it never takes the selected state, and it
/// is drawn at the same weight as its neighbours rather than as a filled
/// button. A single accented circle in the middle of a flat bar is exactly the
/// out-shouting this redraw is removing.
class OmNavBar extends StatelessWidget {
  const OmNavBar({
    super.key,
    required this.current,
    required this.onSelect,
    required this.onAdd,
  });

  final AppTab current;
  final ValueChanged<AppTab> onSelect;

  /// Opens the add sheet. Required: it was optional once, one screen built the
  /// bar without it, and the middle of the bar silently became a hole.
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    const tabs = AppTab.values;
    // The (+) sits in the middle of the finished row, so the tabs either side
    // stay evenly spaced rather than bunching around it.
    final centre = tabs.length ~/ 2;

    // Opaque, and that is not decoration.
    //
    // The shell uses extendBody so the body runs to the bottom of the screen -
    // it was there to give the old frosted capsule something to blur. The bar
    // is flat now, so without a ground of its own the list underneath scrolls
    // straight through the glyphs and the whole bar shimmers as you scroll.
    return ColoredBox(
      color: context.omColors.bg,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              for (var i = 0; i < tabs.length; i++) ...[
                if (i == centre) _AddItem(onTap: onAdd),
                _NavItem(
                  tab: tabs[i],
                  active: tabs[i] == current,
                  onTap: () {
                    if (tabs[i] != current) Haptics.select();
                    onSelect(tabs[i]);
                  },
                ),
              ],
            ],
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
  });

  final AppTab tab;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Semantics(
      label: tab.label,
      button: true,
      selected: active,
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none, // the bar fires its own select haptic
        pressedScale: 0.9,
        child: SizedBox(
          // A 56px square rather than the glyph's own bounds: the icon is small
          // and flat now, so without a deliberate target the bar becomes a row
          // of things you have to aim at.
          width: 56,
          height: 56,
          child: Center(
            child: _NavIcon(
              tab: tab,
              active: active,
              color: active ? c.primary : c.text2,
            ),
          ),
        ),
      ),
    );
  }
}

/// One destination's glyph: outline at rest, solid and in brand when selected.
class _NavIcon extends StatelessWidget {
  const _NavIcon({
    required this.tab,
    required this.active,
    required this.color,
  });

  final AppTab tab;
  final bool active;
  final Color color;

  /// Chat is drawn by hand rather than taken from the icon set.
  ///
  /// Material has no *circular* filled speech bubble, so chat's resting round
  /// outline had to fill into a square `chat_bubble` - a circle that became a
  /// fat rectangular blob the moment you selected it, on the one glyph people
  /// look at most. Both states here are the same round bubble, so selecting it
  /// fills the shape in rather than swapping it for a different shape.
  Widget _glyph({
    required bool filled,
    required Color color,
    required double size,
  }) {
    if (tab == AppTab.coach) {
      // A touch larger than the nominal figure, because the painter's bubble
      // fills less of its box than a Material glyph fills of its own. 1.2 was
      // an overcorrection and made chat the biggest thing in the row; 1.08
      // lands it level with its neighbours.
      return _ChatCircleGlyph(color: color, filled: filled, size: size * 1.08);
    }
    return Icon(filled ? tab.activeIcon : tab.icon, color: color, size: size);
  }

  @override
  Widget build(BuildContext context) {
    // Outline and solid are cross-faded on top of each other rather than
    // swapped, so the glyph fills in instead of popping. There are no labels,
    // so the icon carries the destination alone and the selected one grows a
    // touch to say so.
    return TweenAnimationBuilder<double>(
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
                child: _glyph(filled: false, color: col, size: 25),
              ),
              Opacity(
                opacity: t.clamp(0.0, 1.0),
                child: _glyph(filled: true, color: col, size: 25 + (t * 1.5)),
              ),
            ],
          );
        },
      ),
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

    final bubble = Path()..addOval(Rect.fromCircle(center: centre, radius: r));
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

/// The (+). Same size and weight as a tab, accented rather than filled.
///
/// Labelled, because it is the one control in the bar with no text and no
/// destination: the tabs announce themselves by name, a bare plus announces
/// "button". The flat redraw dropped this label and took the (+) off VoiceOver
/// with it.
class _AddItem extends StatelessWidget {
  const _AddItem({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Semantics(
      label: 'add something',
      button: true,
      child: OmTappable(
        onTap: () {
          Haptics.light();
          onTap();
        },
        feedback: OmTapFeedback.none,
        pressedScale: 0.9,
        child: SizedBox(
          width: 56,
          height: 56,
          child: Center(
            child: Icon(Icons.add_rounded, size: 27, color: c.primary),
          ),
        ),
      ),
    );
  }
}
