import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/mood_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';
import '../../memory/memory_actions.dart';
import 'mood_gauge.dart';

/// Today's mood plus the fortnight behind it.
///
/// The strip is deliberately unlabelled and un-numbered. The value of a mood
/// log for an ADHD brain is seeing the *shape* - "oh, every Tuesday" - not
/// scoring yourself, and gaps are left as gaps because a day you did not open
/// the app is information too.
class MoodBar extends StatelessWidget {
  const MoodBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final mood = context.watch<MoodProvider>();
    final today = mood.today;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: OmTappable(
        onTap: () => showMoodCheckIn(context, replacing: today?.mood),
        feedback: OmTapFeedback.none,
        pressedScale: 0.99,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: context.isDark ? 0.4 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: OmGlass(
            borderRadius: 24,
            blur: 26,
            opacity: context.isDark ? 0.34 : 0.62,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Read(mood: mood, today: today),
                const SizedBox(height: 14),
                SizedBox(
                  height: 34,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final entry in mood.recent)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: _Tick(entry: entry),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'last two weeks',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The dial, and the sentence explaining what it is claiming.
///
/// Three states, and the difference between them is who is talking. If they
/// checked in, the needle is their word and the caption says so. If they have
/// not, it is the app's guess and the caption is the app's reason, hedged out
/// loud - being told how you feel by software is only tolerable when the
/// software shows its working and can be corrected in one tap. With neither,
/// the dial is empty rather than resting at "okay".
class _Read extends StatelessWidget {
  const _Read({required this.mood, required this.today});

  final MoodProvider mood;
  final MoodEntry? today;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final read = mood.reading;
    final mine = today != null;
    final shown = today?.mood ?? read?.mood;

    final String headline;
    final String caption;
    // The mood word itself lives in the middle of the dial, so nothing here
    // repeats it. This side is only ever about who said it and why.
    if (mine) {
      headline = 'your check-in';
      caption = 'you logged this today';
    } else if (read != null) {
      headline = 'my read on today';
      caption = read.why.isEmpty ? 'a guess, from what I have seen' : read.why;
    } else if (mood.predicting) {
      headline = 'reading your week';
      caption = 'one moment';
    } else {
      headline = 'how are you today?';
      caption = 'check in, or give me a few days to learn your shape';
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        MoodGauge(mood: shown, size: 104, pending: mood.predicting),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(headline, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                caption,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: c.text2, height: 1.4),
              ),
              const SizedBox(height: 8),
              Text(
                mine ? 'change' : 'check in',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: c.primary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A mood as a soft gradient orb rather than a yellow face.
///
/// The light source sits off-centre, so the sphere reads as lit from the upper
/// left rather than as a flat disc, and the fill runs coral at "rough" through
/// to brand purple at "great". Emoji were the quick version of this and the
/// wrong one: five system smileys are somebody else's art direction dropped
/// into the middle of the app, and they render differently on every device.
class MoodOrb extends StatelessWidget {
  const MoodOrb({super.key, required this.mood, this.size = 28, this.glow = true});

  /// null renders the "not logged yet" orb: the same shape, drained of colour.
  final Mood? mood;
  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final m = mood;
    final tint = m == null
        ? Color.lerp(c.text2, c.surfaceAlt, 0.55)!
        : Color.lerp(c.accent, c.primary, m.value)!;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          // Offset, not centred: this is what makes it a sphere.
          center: const Alignment(-0.38, -0.45),
          radius: 0.95,
          colors: [
            Color.lerp(tint, Colors.white, 0.72)!,
            tint,
            Color.lerp(tint, const Color(0xFF1B1033), 0.34)!,
          ],
          stops: const [0.0, 0.52, 1.0],
        ),
        boxShadow: glow
            ? [
                BoxShadow(
                  color: tint.withValues(alpha: m == null ? 0.14 : 0.42),
                  blurRadius: size * 0.5,
                  spreadRadius: -size * 0.12,
                  offset: Offset(0, size * 0.22),
                ),
              ]
            : null,
      ),
    );
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.entry});

  final MoodEntry? entry;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final e = entry;
    if (e == null) {
      // A missed day: a flat stub, not a zero-height bar, so the strip keeps
      // its rhythm and a gap does not read as "rough".
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 4,
          decoration: BoxDecoration(
            color: c.ringTrack,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
    }
    // Rough → coral, great → brand purple, so the strip reads as one gradient
    // of feeling rather than a traffic light.
    final tint = Color.lerp(c.accent, c.primary, e.mood.value)!;
    return Align(
      alignment: Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
        tween: Tween(end: e.mood.value),
        builder: (context, v, _) => Container(
          height: 8 + (26 * v),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [tint, Color.lerp(tint, Colors.white, 0.35)!],
            ),
            // Softly rounded, not a capsule: at these widths a pill radius
            // turns every tick into a dot and the trend stops reading.
            borderRadius: BorderRadius.circular(5),
          ),
        ),
      ),
    );
  }
}

/// The once-a-day check-in. Five faces, one tap, no typing required - a note is
/// there for the days someone wants it, and ignored otherwise.
Future<void> showMoodCheckIn(BuildContext context, {Mood? replacing}) {
  final provider = context.read<MoodProvider>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      final c = sheetContext.omColors;
      var selected = replacing;
      return StatefulBuilder(
        builder: (ctx, setState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('how are you today?',
                    style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('drag the dial. no wrong answer, and you can change it later.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.lg),
                Center(
                  child: MoodDialPicker(
                    initial: selected,
                    onChanged: (m) => setState(() => selected = m),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected == null
                        ? null
                        : () {
                            Haptics.success();
                            provider.checkIn(selected!);
                            Navigator.of(ctx).pop();
                            // Fold the just-logged mood into the memory now
                            // rather than waiting on the autopilot's 8-minute
                            // cooldown: a check-in is the user stating outright
                            // how they are, and the coach should carry it into
                            // the very next message. Uses the outer context,
                            // which outlives the sheet.
                            refreshMemory(context, haptic: false, quiet: true);
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: c.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('log it'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
