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
    final tint = shown == null
        ? Color.lerp(c.text2, c.surfaceAlt, 0.5)!
        : Color.lerp(c.accent, c.primary, shown.value)!;

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

/// The rail, its filled portion, and the knob.
class _Track extends StatelessWidget {
  const _Track({required this.mood, required this.tint, required this.width});

  final Mood? mood;
  final Color tint;
  final double width;

  static const _rail = 12.0;
  static const _knob = 28.0;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // The centre of the mood's own slot, so the knob sits over the stretch of
    // track that selects it rather than at an edge shared with its neighbour.
    final t = mood == null ? null : (Mood.values.indexOf(mood!) + 0.5) / 5;

    return SizedBox(
      height: _knob + 8,
      width: width,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // The rail.
          Container(
            height: _rail,
            decoration: BoxDecoration(
              color: c.text2.withValues(alpha: context.isDark ? 0.22 : 0.13),
              borderRadius: BorderRadius.circular(_rail),
            ),
          ),
          // Five notches, so the range reads as five answers rather than a
          // continuum somebody has to be precise about.
          Row(
            children: [
              for (var i = 0; i < 5; i++)
                Expanded(
                  child: Center(
                    child: Container(
                      width: 3,
                      height: 3,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: c.text2.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          if (t != null) ...[
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              height: _rail,
              width: (width * t).clamp(_knob, width),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color.lerp(c.accent, tint, 0.35)!,
                    tint,
                  ],
                ),
                borderRadius: BorderRadius.circular(_rail),
              ),
            ),
            AnimatedPositioned(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              left: (width * t - _knob / 2).clamp(0.0, width - _knob),
              child: _Knob(tint: tint, size: _knob),
            ),
          ],
        ],
      ),
    );
  }
}

/// The knob, lit from the same off-centre point as the mood orbs so the two
/// read as the same material rather than two designers' work.
class _Knob extends StatelessWidget {
  const _Knob({required this.tint, required this.size});

  final Color tint;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 0.95,
          colors: [
            Color.lerp(tint, Colors.white, 0.72)!,
            tint,
            Color.lerp(tint, const Color(0xFF1B1033), 0.24)!,
          ],
          stops: const [0, 0.55, 1],
        ),
        boxShadow: [
          BoxShadow(
            color: tint.withValues(alpha: 0.42),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
    );
  }
}
