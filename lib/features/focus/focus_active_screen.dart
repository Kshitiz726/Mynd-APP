import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../providers/focus_provider.dart';
import '../../providers/nav_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_tappable.dart';
import 'focus_help.dart';

class FocusActiveScreen extends StatelessWidget {
  const FocusActiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusProvider>();
    final currentTask = context.watch<TaskProvider>().upNext?.title;

    // Scrollable + min-height so the layout breathes on tall screens but never
    // overflows / blocks scrolling on short ones.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  // Top row: a Back exit that LEAVES the session running (it keeps
                  // ticking and the live pill brings you back), plus body-doubling status.
                  Row(
                    children: [
                      _RoundIconButton(
                        icon: 'chevL',
                        label: 'back',
                        onTap: () {
                          Haptics.light();
                          context.read<NavProvider>().select(AppTab.today);
                        },
                      ),
                      const Spacer(),
                      if (focus.partnerName != null) 
                        Text('focusing with ${focus.partnerName}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: context.omColors.primary)),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text('locked in on',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          )),
                  const SizedBox(height: 8),
                  Text(
                    currentTask ?? 'this focus session',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  const SizedBox(height: AppSpacing.xl),
                  _TimerCircle(
                    progress: 1 -
                        (focus.secondsRemaining /
                            ((focus.activeMode?.minutes ?? 1) * 60)),
                    time: focus.timeString,
                    running: focus.isRunning,
                  ),
                  const Spacer(),
                  const SizedBox(height: AppSpacing.xl),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: focus.isRunning ? 'pause' : 'resume',
                          icon: focus.isRunning ? 'pause' : 'play',
                          onTap: () {
                            Haptics.medium();
                            focus.togglePause();
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _ActionButton(
                          label: 'end',
                          icon: 'close',
                          onTap: () {
                            Haptics.medium();
                            focus.end();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _ActionButton(
                    label: 'park a thought',
                    icon: 'edit',
                    onTap: () {
                      Haptics.light();
                      Toast.show(context, 'Thought parked!');
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OmTappable(
                    onTap: () => askMyndForHelp(context),
                    feedback: OmTapFeedback.light,
                    pressedScale: 0.96,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(OmIcons.byName('life-buoy'), size: 16, color: context.omColors.primary),
                          const SizedBox(width: 6),
                          Text('Need help? Talk to Mynd',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: context.omColors.primary,
                                    fontWeight: FontWeight.w700,
                                  )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'brain pinging you? park it without leaving - it drops to your inbox.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                  const SizedBox(height: AppSpacing.screenBottom / 2),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A pill back/exit button. Leaving here does NOT end the session.
class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.label, required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.94,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(OmIcons.byName(icon), size: 18, color: c.text),
            const SizedBox(width: 4),
            Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _TimerCircle extends StatelessWidget {
  const _TimerCircle({required this.progress, required this.time, required this.running});

  final double progress;
  final String time;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Soft glow halo.
        Container(
          width: 248,
          height: 248,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: running ? 0.18 : 0.08),
                blurRadius: 40,
                spreadRadius: 4,
              ),
            ],
          ),
        ),
        SizedBox(
          width: 232,
          height: 232,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 14,
              strokeCap: StrokeCap.round,
              backgroundColor: c.primary.withValues(alpha: 0.14),
              valueColor: AlwaysStoppedAnimation<Color>(c.primary),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontSize: 48, fontWeight: FontWeight.w800, letterSpacing: -1),
            ),
            Text('remaining',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: c.text2,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    )),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.onTap, required this.icon});

  final String label;
  final String icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      feedback: OmTapFeedback.none,
      pressedScale: 0.96,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 5)),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(OmIcons.byName(icon), size: 19, color: c.text),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
