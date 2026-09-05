import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/mood_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';
import '../../memory/memory_actions.dart';

/// Today's check-in: one question, five faces.
///
/// This replaces a five segment bar. The bar worked and said nothing: a row of
/// equal rectangles is a volume control, and the thing being asked about is
/// not a quantity. Reading your own mood off how many boxes are lit is a
/// translation step at the exact moment somebody is least inclined to do one.
///
/// Faces answer before they are read, which is the whole reason this is one
/// short row and not a card. Two earlier drafts were taller: one gave the
/// chosen mood a hero portrait with its name underneath, the other hung the
/// five faces off a curve. Both were handsome and both spent most of a screen
/// on a question that takes one tap, on the screen where somebody is trying to
/// get to their day. The scale reads perfectly well flat, because the faces
/// carry it.
class MoodPicker extends StatelessWidget {
  const MoodPicker({super.key});

  /// One hue, five depths.
  ///
  /// Not a hue ramp. Blending peach into periwinkle put a muddy mauve in the
  /// middle of the scale, which is both the ugliest point on it and the most
  /// common answer. Depth of the brand colour says "more" without inventing a
  /// second colour, and it keeps a rough day quiet rather than alarming: this
  /// is a check-in, not a warning light.
  static Color tintFor(BuildContext context, Mood m) {
    final c = context.omColors;
    return Color.lerp(c.primaryTint, c.primary, 0.46 + 0.54 * (m.index / 4))!;
  }

  void _pick(BuildContext context, Mood m) {
    Haptics.success();
    context.read<MoodProvider>().checkIn(m);
    // Folded into the memory now rather than on the autopilot's cooldown: a
    // check-in is somebody stating outright how they are, and the coach should
    // be carrying it by the very next message.
    refreshMemory(context, haptic: false, quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final shown = context.watch<MoodProvider>().today?.mood;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: context.isDark ? 0.38 : 0.07),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: OmGlass(
          borderRadius: 22,
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                // Left, against the faces below. The default layout stacks the
                // outgoing and incoming text centred, which floated the
                // sentence into the middle of the card.
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, if (current != null) current],
                ),
                child: Text(
                  shown == null
                      ? 'how are you today?'
                      : 'today you are ${shown.label}',
                  key: ValueKey(shown?.label),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                    color: shown == null ? c.text2 : c.text,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final m in Mood.values)
                    _Choice(
                      mood: m,
                      size: 38,
                      selected: m == shown,
                      onTap: () => _pick(context, m),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.mood,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final Mood mood;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Semantics(
      button: true,
      selected: selected,
      label: mood.label,
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none,
        pressedScale: 0.9,
        child: AnimatedScale(
          scale: selected ? 1.0 : 0.88,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            // The unchosen fade back rather than greying out. A row of
            // equally loud faces is a row of demands.
            opacity: selected ? 1 : 0.68,
            duration: const Duration(milliseconds: 200),
            child: _Face(
              mood: mood,
              size: size,
              fill: MoodPicker.tintFor(context, mood),
              ring: selected ? c.primary : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// A filled circle with a drawn expression.
///
/// Drawn rather than an emoji on purpose: emoji are somebody else's artwork,
/// they change between OS versions, and five of them side by side never share
/// a palette. Two eyes and one curve stay on brand and carry the whole range.
class _Face extends StatelessWidget {
  const _Face({
    required this.mood,
    required this.size,
    required this.fill,
    this.ring,
  });

  final Mood? mood;
  final double size;
  final Color fill;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill,
        border: ring == null ? null : Border.all(color: ring!, width: 2),
      ),
      child: CustomPaint(
        painter: _FacePainter(
          mood: mood,
          ink: Colors.white.withValues(alpha: 0.92),
        ),
      ),
    );
  }
}

class _FacePainter extends CustomPainter {
  _FacePainter({required this.mood, required this.ink});

  final Mood? mood;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final eyeY = w * 0.40;
    final eyeDx = w * 0.20;
    final r = w * 0.045;
    final p = Paint()..color = ink;

    canvas.drawCircle(Offset(w / 2 - eyeDx, eyeY), r, p);
    canvas.drawCircle(Offset(w / 2 + eyeDx, eyeY), r, p);

    // Nothing chosen: a level line, which is neither a smile nor a frown and
    // so is not an answer on somebody's behalf.
    final curve = mood == null ? 0.0 : (mood!.index - 2) / 2;
    final mouth = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.055
      ..strokeCap = StrokeCap.round
      ..color = ink;

    final left = Offset(w / 2 - w * 0.19, w * 0.62);
    final right = Offset(w / 2 + w * 0.19, w * 0.62);
    canvas.drawPath(
      Path()
        ..moveTo(left.dx, left.dy)
        ..quadraticBezierTo(w / 2, w * 0.62 + curve * w * 0.22, right.dx, right.dy),
      mouth,
    );
  }

  @override
  bool shouldRepaint(_FacePainter old) => old.mood != mood || old.ink != ink;
}
