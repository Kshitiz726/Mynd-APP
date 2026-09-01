import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/mood_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../memory/memory_actions.dart';

/// Today's check-in, sitting under the orb rather than jumping in front of it.
///
/// This replaces a modal sheet that opened on the first launch of every day.
/// Being asked "how are you today?" before you have even reached the app is
/// the wrong shape for the question: it interrupts whatever you opened the app
/// to do, and on the days worth noticing it is the most likely thing to be
/// dismissed. Here the question is simply present, answerable in one drag, and
/// ignorable forever.
///
/// Horizontal on purpose. A dial is a lovely object and a poor control on a
/// phone: the thumb travels an arc while the finger travels a straight line, so
/// the two disagree the moment the gesture is anything but slow and deliberate.
/// A track moves exactly with the finger.
///
/// It logs on release rather than on every step. Dragging across the range
/// passes through three moods that were never meant, and writing each one would
/// put moods in the history nobody chose.
class MoodSlider extends StatefulWidget {
  const MoodSlider({super.key});

  @override
  State<MoodSlider> createState() => _MoodSliderState();
}

class _MoodSliderState extends State<MoodSlider> {
  /// What the thumb is showing, which during a drag is ahead of what is
  /// stored. Null means nothing has been logged today and there is no thumb to
  /// show: a thumb parked in the middle is a claim that you are "okay", and
  /// that is exactly the wrong thing to tell somebody who is not.
  Mood? _dragging;

  Mood? _stored(BuildContext context) => context.watch<MoodProvider>().today?.mood;

  /// Where the touch fell, as a mood.
  Mood _moodAt(double dx, double width) {
    // Half a step of padding at each end, so the first and last moods have the
    // same amount of track to hit as the three in the middle.
    const n = 5;
    final step = width / n;
    final i = (dx / step).floor().clamp(0, n - 1);
    return Mood.values[i];
  }

  void _update(double dx, double width) {
    final next = _moodAt(dx, width);
    if (next == _dragging) return;
    Haptics.select();
    setState(() => _dragging = next);
  }

  void _commit(BuildContext context) {
    final picked = _dragging;
    if (picked == null) return;
    Haptics.success();
    context.read<MoodProvider>().checkIn(picked);
    // Fold it into the memory now rather than waiting on the autopilot's
    // cooldown: a check-in is somebody stating outright how they are, and the
    // coach should carry it into the very next message.
    refreshMemory(context, haptic: false, quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final shown = _dragging ?? _stored(context);
    // One colour for every level, not a ramp. Blending peach into periwinkle
    // put a muddy mauve in the middle of the scale, which is both the ugliest
    // point and the most common answer. The brand colour throughout keeps it
    // calm, and the level is already said twice over: by how many segments are
    // filled, and by the word next to them.
    final tint = shown == null ? c.text2.withValues(alpha: 0.5) : c.primary;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: context.isDark ? 0.38 : 0.07),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: OmGlass(
          borderRadius: 26,
          // The pane stays neutral and only the fill, the knob and the word
          // carry the colour. Washing the whole surface with the mood was the
          // first attempt and it read as a coloured slab sitting among glass
          // cards rather than one of them, which is also how iOS treats a
          // slider: neutral chrome, tinted track.
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    shown == null ? 'how are you?' : 'today you are',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                      color: c.text2,
                    ),
                  ),
                  const Spacer(),
                  // The word, not a number. Scoring a feeling out of five is
                  // the thing this control exists to avoid.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    child: Text(
                      shown?.label ?? 'drag to say',
                      key: ValueKey(shown),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: shown == null ? c.text2 : tint,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) {
                  final w = box.maxWidth;
                  return GestureDetector(
                    // A drag, not a tap, so OmTappable is the wrong tool: it
                    // has no notion of a finger that keeps moving. Everything
                    // in this app that a finger drags along uses a raw
                    // recogniser for the same reason.
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (d) => _update(d.localPosition.dx, w),
                    onTapUp: (_) => _commit(context),
                    onHorizontalDragStart: (d) =>
                        _update(d.localPosition.dx, w),
                    onHorizontalDragUpdate: (d) =>
                        _update(d.localPosition.dx, w),
                    onHorizontalDragEnd: (_) => _commit(context),
                    child: _Track(mood: shown, tint: tint, width: w),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Five segments that fill up to the level chosen.
///
/// A bar of steps rather than a rail with a knob. The knob was a shaded sphere
/// with a glow, and next to flat cards it read as a control borrowed from
/// another app: the eye went to the object instead of to the answer. Segments
/// say the same thing with nothing to look at, and they show the scale is five
/// wide without needing a legend.
class _Track extends StatelessWidget {
  const _Track({required this.mood, required this.tint, required this.width});

  final Mood? mood;
  final Color tint;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final level = mood == null ? -1 : Mood.values.indexOf(mood!);

    return SizedBox(
      height: 30,
      width: width,
      child: Row(
        children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                curve: Curves.easeOutCubic,
                // The filled segments rise slightly towards the chosen one, so
                // the level reads at a glance without any number on it.
                height: i <= level ? 14.0 + i : 10,
                decoration: BoxDecoration(
                  color: i <= level
                      ? tint
                      : c.text2.withValues(alpha: context.isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
