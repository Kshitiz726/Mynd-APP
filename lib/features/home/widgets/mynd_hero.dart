import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/glow_ring.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';
import '../../memory/memory_actions.dart';
import 'voice_dump_sheet.dart';

/// The top of Home: Mynd itself, the day's count, and a way to make it think
/// again.
///
/// What was here before was a flat gradient circle with a drawn-on smile whose
/// mouth curved with your energy level, and a pill underneath naming that
/// energy. Two problems. The face was a sticker, not a presence, and it was the
/// first thing anyone saw. And the pill said "high energy" directly above cards
/// that already say how the day is going, so the most prominent thing on the
/// page was also the most redundant.
///
/// Now it is the same living orb the coach has, so Mynd has one face
/// everywhere, sitting in a slow aurora that drifts whether or not you touch
/// it. Touching it makes it answer. The pill is gone and a refresh sits in its
/// place, because "think about me again" is a thing worth having on the front
/// page and "you said you had energy" is not.
class MyndHero extends StatefulWidget {
  const MyndHero({super.key});

  @override
  State<MyndHero> createState() => _MyndHeroState();
}

class _MyndHeroState extends State<MyndHero> with TickerProviderStateMixin {
  /// The idle drift. Never stops, never repeats where you expect, because two
  /// rings turning at unrelated speeds do not come back into phase for a long
  /// time.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat();

  /// The reload. Runs once per press and is what the orb is doing while the
  /// app actually re-reads you.
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  bool _busy = false;

  @override
  void dispose() {
    _drift.dispose();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_busy) return;
    Haptics.medium();
    setState(() => _busy = true);
    _pulse.repeat();
    try {
      // The two things the app believes about you, both rebuilt from the same
      // picture. Called directly rather than through the autopilot, which is
      // the point of a button: pressing it means now, not when the cooldown
      // says so.
      await refreshMemory(context, haptic: false, quiet: true);
      if (mounted) await readMood(context);
    } finally {
      if (mounted) {
        // Let the current turn finish rather than cutting the light off
        // mid-sweep, which is what makes a loading state feel mechanical.
        await _pulse.forward(from: _pulse.value);
        if (mounted) setState(() => _busy = false);
        _pulse.reset();
      }
    }
  }

  /// Tapping the ring is the fastest way to offload a head full of stuff: it
  /// opens the voice dump, you talk, and Groq breaks it into today's tasks, the
  /// same as typing into Brain Dump but hands-free.
  ///
  /// Deliberately not gated on [_busy]. It used to be, which meant a memory
  /// rewrite running in the background took the mic offline, and a rewrite that
  /// never came back took it offline for good: the one button somebody presses
  /// when their head is full went dead because of a request they never asked
  /// for and cannot see. The two actions have nothing to do with each other.
  void _voiceDump() {
    Haptics.medium();
    _pulse.forward(from: 0);
    showVoiceDumpSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final goals = context.watch<GoalProvider>().activeCount;
    final done = tasks.doneCount;
    final scheduled = tasks.daySchedule.length;
    final total = done + scheduled;
    final pct = total == 0 ? 0.0 : done / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.sm),
        // The count, at the size the reference gives its headline. It used to
        // sit under a 124px rendered marble, which meant the first thing on
        // the page was decoration and the actual state of the day was a
        // caption to it. This is the other way round.
        Text(
          '$done done today',
          style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                fontSize: 34,
                height: 1.05,
                letterSpacing: -1.1,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          '$scheduled scheduled  ·  $goals goals',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: c.text2, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: AppSpacing.lg),
        _TodayCard(
          done: done,
          total: total,
          pct: pct,
          busy: _busy,
          spin: _pulse,
          onSpeak: _voiceDump,
          onReload: _reload,
        ),
      ],
    );
  }
}

/// Today, as one soft card: how far through it you are, and the way in.
///
/// The glowing disc on the right is the orb's replacement and carries the
/// orb's job. Tapping the marble opened the voice sheet, which nothing about
/// a marble suggested; a lit circle with a microphone in it says so plainly,
/// and it sits where the eye already goes after reading the line beside it.
class _TodayCard extends StatelessWidget {
  const _TodayCard({
    required this.done,
    required this.total,
    required this.pct,
    required this.busy,
    required this.spin,
    required this.onSpeak,
    required this.onReload,
  });

  final int done;
  final int total;
  final double pct;
  final bool busy;

  /// Drives the refresh badge's turn. Shared with the memory rewrite it starts,
  /// so the icon is moving for exactly as long as the app is thinking.
  final Animation<double> spin;
  final VoidCallback onSpeak;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: context.isDark ? 0.38 : 0.07),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: OmGlass(
        borderRadius: 28,
        padding: const EdgeInsets.fromLTRB(20, 18, 18, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    total == 0
                        // Nothing blocked in is not zero percent of anything,
                        // and telling somebody they are 0% through their day
                        // before they have planned it is a scolding.
                        ? 'nothing blocked in yet'
                        : "you're ${(pct * 100).round()}% through today",
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _Bar(pct: pct, label: total == 0 ? null : '$done/$total'),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            // Refresh hangs off the disc's rim, where the streak flame used
            // to. The flame was already on the top bar reading the same
            // provider, so it was the same number twice; refresh was a whole
            // pill on a row of its own, and that row was what pushed "do this
            // now" off the first screen. One rim, one badge, one row saved.
            SizedBox(
              width: 84,
              height: 84,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GlowRing(
                    size: 84,
                    icon: OmIcons.byName('mic'),
                    active: busy,
                    onTap: onSpeak,
                    semanticLabel: 'speak a thought',
                  ),
                  Positioned(
                    right: -6,
                    bottom: -2,
                    child: _RefreshBadge(
                      busy: busy,
                      spin: spin,
                      onTap: onReload,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.pct, this.label});

  final double pct;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Stack(
              children: [
                Container(
                  height: 12,
                  color: c.text2.withValues(alpha: context.isDark ? 0.18 : 0.10),
                ),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: pct.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 750),
                  curve: Curves.easeOutCubic,
                  builder: (context, v, _) => FractionallySizedBox(
                    widthFactor: v == 0 ? 0.0001 : v,
                    child: Container(
                      height: 12,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [c.primary, Color.lerp(c.primary, c.accent, 0.5)!],
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 10),
          Text(
            label!,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: c.text2,
            ),
          ),
        ],
      ],
    );
  }
}

/// Refresh, worn on the mic's rim.
///
/// It was a labelled glass pill under the card, on the grounds that a lone
/// circular arrow reads as "reload the page". That argument was right about
/// the icon and wrong about the price: the pill cost a whole row on the one
/// screen where rows are scarce, to explain a control most people press once.
/// On the rim it is attached to the thing it makes think, the icon turns for
/// as long as the rewrite runs, and it still says what it is to a screen
/// reader.
class _RefreshBadge extends StatelessWidget {
  const _RefreshBadge({
    required this.busy,
    required this.spin,
    required this.onTap,
  });

  final bool busy;
  final Animation<double> spin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Semantics(
      button: true,
      label: busy ? 'refreshing your memory' : 'refresh memory',
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none,
        pressedScale: 0.9,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: busy ? c.primary : c.surface,
            // A hairline in the page's own ink, so the badge sits ON the disc
            // rather than looking like a hole cut out of it.
            border: Border.all(
              color: busy ? c.primary : c.border,
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: context.isDark ? 0.5 : 0.14),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: AnimatedBuilder(
            animation: spin,
            builder: (context, child) => Transform.rotate(
              // Eased, not linear. A constant-speed spinner is the mechanical
              // thing; this leans into the turn and settles out of it, like
              // something being wound.
              angle: Curves.easeInOutCubic.transform(spin.value) * math.pi * 2,
              child: child,
            ),
            child: Icon(
              OmIcons.byName('refresh'),
              size: 17,
              color: busy ? Colors.white : c.primary,
            ),
          ),
        ),
      ),
    );
  }
}
