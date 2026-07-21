import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/mood_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';

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
                Row(
                  children: [
                    Text(
                      today?.mood.emoji ?? '🫥',
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        today == null
                            ? 'how are you today?'
                            : 'today feels ${today.mood.label}',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    Text(
                      today == null ? 'check in' : 'change',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: c.primary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ],
                ),
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
                Text('one tap. no wrong answer, and you can change it later.',
                    style: Theme.of(ctx).textTheme.bodySmall),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    for (final m in Mood.values)
                      OmTappable(
                        onTap: () {
                          Haptics.select();
                          setState(() => selected = m);
                        },
                        feedback: OmTapFeedback.none,
                        pressedScale: 0.88,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          width: 58,
                          height: 72,
                          decoration: BoxDecoration(
                            color: selected == m ? c.primaryTint : c.surfaceAlt,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: selected == m ? c.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(m.emoji, style: const TextStyle(fontSize: 24)),
                              const SizedBox(height: 6),
                              Text(
                                m.label,
                                style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                      color: selected == m ? c.primary : c.text2,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 10,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
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
