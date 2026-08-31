import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/focus_ambience.dart';
import '../../providers/focus_provider.dart';
import 'widgets/focus_music.dart';
import '../../providers/nav_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import 'focus_help.dart';
import 'park_thought_sheet.dart';

class FocusActiveScreen extends StatelessWidget {
  const FocusActiveScreen({super.key});

  /// Confirm before a *back press* ends the running session. Only the back
  /// affordance (system back or the on-screen chevron) asks this - closing the
  /// app, switching away, or opening "talk to Mynd" never do.
  static Future<bool> _confirmExit(BuildContext context) async {
    final c = context.omColors;
    final leave = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (dialogContext) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('End this focus?'),
        content: const Text(
          'Going back will end your focus session. Your time so far is saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('keep focusing', style: TextStyle(color: c.text2, fontWeight: FontWeight.w700)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text('end session', style: TextStyle(color: c.error, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    return leave ?? false;
  }

  static void _handleBack(BuildContext context) async {
    Haptics.light();
    if (await _confirmExit(context) && context.mounted) {
      context.read<FocusProvider>().end();
    }
  }

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusProvider>();
    final c = context.omColors;
    // Only intercept back when this running session is actually the screen the
    // user is looking at (the focus tab). Elsewhere, back behaves normally.
    final onFocusTab = context.watch<NavProvider>().tab == AppTab.focus;

    // What the session was started for wins over "up next": if you tapped
    // "focus on this task", that task is what you are locked in on.
    final currentTask = focus.activeTaskTitle ?? context.watch<TaskProvider>().upNext?.title;

    // When a scene is playing the whole screen becomes an image slideshow, so
    // the text flips to white over a dark scrim for legibility.
    final ambience = focus.ambience;
    final onScene = ambience.hasScene;
    final labelColor = onScene ? Colors.white70 : c.text2;
    final titleColor = onScene ? Colors.white : c.text;

    final content = LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  // Room for the fixed top-left back button (overlaid below).
                  const SizedBox(height: 52),
                  // Who you're focusing with (or that we're still matching one).
                  if (focus.bodyDoubling) ...[
                    _PartnerStrip(onScene: onScene),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text('locked in on',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                            color: labelColor,
                          )),
                  const SizedBox(height: 8),
                  Text(
                    currentTask ?? 'this focus session',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: titleColor),
                  ),
                  const Spacer(),
                  const SizedBox(height: AppSpacing.xl),
                  _TimerCircle(
                    progress: 1 - (focus.secondsRemaining / focus.totalSeconds),
                    time: focus.timeString,
                    running: focus.isRunning,
                    onScene: onScene,
                    matching: focus.bodyDoubling && focus.searchingPartner,
                  ),
                  const Spacer(),
                  const SizedBox(height: AppSpacing.lg),
                  // Switch the scene without leaving: drag the thumb across.
                  _AmbienceDragBar(
                    selectedId: ambience.id,
                    onScene: onScene,
                    onSelect: (id) {
                      Haptics.select();
                      context.read<FocusProvider>().setAmbience(id);
                    },
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: _ActionButton(
                          label: focus.isRunning ? 'pause' : 'resume',
                          icon: focus.isRunning ? 'pause' : 'play',
                          onScene: onScene,
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
                          onScene: onScene,
                          onTap: () {
                            Haptics.medium();
                            focus.end();
                          },
                        ),
                      ),
                    ],
                  ),
                  // Between the timer controls and the secondary actions: reachable
                  // without hunting, but below the thing the session is actually
                  // about. Same widget the room uses, so the two cannot drift apart.
                  const SizedBox(height: AppSpacing.md),
                  const SoloMusicStrip(),
                  const SizedBox(height: AppSpacing.md),
                  _ActionButton(
                    label: 'park a thought',
                    icon: 'edit',
                    onScene: onScene,
                    onTap: () => showParkThoughtSheet(context),
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
                          Icon(OmIcons.byName('life-buoy'),
                              size: 16, color: onScene ? Colors.white : c.primary),
                          const SizedBox(width: 6),
                          Text('Need help? Talk to Mynd',
                              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: onScene ? Colors.white : c.primary,
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          color: onScene ? Colors.white70 : null,
                        ),
                  ),
                  const SizedBox(height: AppSpacing.screenBottom / 2),
                ],
              ),
            ),
          ),
        );
      },
    );

    // The scene: a colourful full-screen gradient (recolours live when the
    // ambience is switched), a soft dark scrim so white text stays legible,
    // then the timer and controls on top.
    final body = !onScene
        ? content
        : Stack(
            fit: StackFit.expand,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(gradient: ambience.gradient),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.22),
                        Colors.black.withValues(alpha: 0.4),
                      ],
                    ),
                  ),
                ),
              ),
              content,
            ],
          );

    // Back press ends the session (with a confirm) only while this is the
    // focused tab; everywhere else the gesture behaves normally. The back
    // affordance is pinned top-left over everything, in the app's standard
    // position, rather than shoved into the scrolling content.
    return PopScope(
      canPop: !onFocusTab,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmExit(context) && context.mounted) {
          context.read<FocusProvider>().end();
        }
      },
      child: Stack(
        children: [
          Positioned.fill(child: body),
          Positioned(
            top: 8,
            left: 8,
            child: OmBackButton(onTap: () => _handleBack(context)),
          ),
        ],
      ),
    );
  }
}

/// A compact "focusing with …" strip: the partner's avatar and name plus the
/// work they're on, or the live "matching" state, or the brief "finished their
/// work" hand-off before we quietly re-match.
class _PartnerStrip extends StatelessWidget {
  const _PartnerStrip({required this.onScene});

  final bool onScene;

  static Color _hex(String? s) {
    if (s == null) return const Color(0xFF6366F1);
    var h = s.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFF6366F1) : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusProvider>();
    final c = context.omColors;
    final partner = focus.partner;
    final fg = onScene ? Colors.white : c.text;
    final sub = onScene ? Colors.white70 : c.text2;

    final bg = onScene
        ? Colors.white.withValues(alpha: 0.12)
        : c.surfaceAlt;
    final border = onScene ? Colors.white.withValues(alpha: 0.18) : c.border;

    Widget wrap(Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: border),
          ),
          child: child,
        );

    // Still searching, nobody paired yet.
    if (partner == null) {
      return wrap(Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 1.8, color: onScene ? Colors.white70 : c.primary),
          ),
          const SizedBox(width: 10),
          Text('matching you with a focus partner…',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: sub)),
        ],
      ));
    }

    return wrap(Row(
      children: [
        OmAvatar(
          userId: partner.id,
          fallbackInitial: partner.initial,
          fallbackColor: _hex(partner.color),
          size: 38,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                focus.partnerLeft
                    ? '${partner.name} left'
                    : 'focusing with ${partner.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: fg, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 1),
              Text(
                focus.partnerLeft
                    ? 'go back to match with someone new'
                    : (focus.partnerTask ?? 'working alongside you'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: sub),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          OmIcons.byName(focus.partnerLeft ? 'logout' : 'users'),
          size: 18,
          color: onScene ? Colors.white70 : c.primary,
        ),
      ],
    ));
  }
}

/// A glassy, draggable ambience selector: slide the thumb across the icons to
/// change the scene live while you keep focusing.
class _AmbienceDragBar extends StatelessWidget {
  const _AmbienceDragBar({
    required this.selectedId,
    required this.onSelect,
    required this.onScene,
  });

  final String selectedId;
  final ValueChanged<String> onSelect;
  final bool onScene;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    const items = kFocusAmbiences;
    final n = items.length;
    final selectedIndex = items.indexWhere((a) => a.id == selectedId).clamp(0, n - 1);

    final trackBg = onScene ? Colors.white.withValues(alpha: 0.14) : c.surfaceAlt;
    final trackBorder = onScene ? Colors.white.withValues(alpha: 0.2) : c.border;
    final iconIdle = onScene ? Colors.white70 : c.text2;

    // Slot width is only for mapping a drag/tap x to an icon index; the icons
    // themselves are Expanded so they always fill the bar exactly (no overflow).
    // Deriving width from MediaQuery rather than a LayoutBuilder is deliberate:
    // this bar lives inside the screen's IntrinsicHeight column, and
    // IntrinsicHeight cannot measure a LayoutBuilder - doing so silently blanks
    // the whole timer screen.
    final barWidth = MediaQuery.of(context).size.width - AppSpacing.screenH * 2;
    void selectAt(double dx) {
      final i = (dx / (barWidth / n)).floor().clamp(0, n - 1);
      if (items[i].id != selectedId) onSelect(items[i].id);
    }
    // The selected scene is now marked by tinting its own icon the brand colour
    // (a bright violet-white blend over a scene so it reads on the artwork),
    // rather than sliding a circular thumb behind it.
    final iconSelected =
        onScene ? Color.lerp(c.primary, Colors.white, 0.55)! : c.primary;

    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => selectAt(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => selectAt(d.localPosition.dx),
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: trackBg,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: trackBorder),
            ),
            child: Row(
              children: [
                for (var i = 0; i < n; i++)
                  Expanded(
                    child: Center(
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        scale: i == selectedIndex ? 1.25 : 1.0,
                        child: Icon(
                          OmIcons.byName(items[i].icon),
                          size: 20,
                          color: i == selectedIndex ? iconSelected : iconIdle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          items[selectedIndex].id == 'none'
              ? 'no scene · drag to add ambience'
              : '${items[selectedIndex].label} · drag to switch',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: onScene ? Colors.white70 : c.text2,
              ),
        ),
      ],
    );
  }
}

class _TimerCircle extends StatelessWidget {
  const _TimerCircle({
    required this.progress,
    required this.time,
    required this.running,
    this.onScene = false,
    this.matching = false,
  });

  final double progress;
  final String time;
  final bool running;
  final bool onScene;
  final bool matching;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // The ring reads as white over a scene, brand purple on the card.
    final ringColor = onScene ? Colors.white : c.primary;
    final trackColor = onScene
        ? Colors.white.withValues(alpha: 0.22)
        : c.primary.withValues(alpha: 0.14);
    final timeColor = onScene ? Colors.white : c.text;
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
                color: ringColor.withValues(alpha: running ? 0.18 : 0.08),
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
              backgroundColor: trackColor,
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
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
                  // Hour-long sessions read as "1:59:40", which needs the smaller size.
                  ?.copyWith(
                    fontSize: time.length > 5 ? 40 : 48,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -1,
                    color: timeColor,
                  ),
            ),
            // "matching…" lives inside the ring so the search never covers the
            // clock and never interrupts the running session.
            if (matching)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: onScene ? Colors.white70 : c.primary),
                    ),
                    const SizedBox(width: 6),
                    Text('matching…',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: onScene ? Colors.white70 : c.primary,
                              fontSize: 12,
                              letterSpacing: 0.5,
                            )),
                  ],
                ),
              )
            else
              Text('remaining',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: onScene ? Colors.white70 : c.text2,
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
  const _ActionButton({
    required this.label,
    required this.onTap,
    required this.icon,
    this.onScene = false,
  });

  final String label;
  final String icon;
  final bool onScene;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // One consistent button family in every ambience: a flat, bordered surface
    // (no elevation on "none", no washed translucency on scenes). Only the
    // colours shift for legibility - the shape, weight and border stay put, so
    // switching the scene no longer restyles the controls under you.
    final bg = onScene ? Colors.white.withValues(alpha: 0.20) : c.surface;
    final border = onScene ? Colors.white.withValues(alpha: 0.32) : c.border;
    final fg = onScene ? Colors.white : c.text;
    return OmTappable(
      feedback: OmTapFeedback.none,
      pressedScale: 0.96,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        // A true pill: StadiumBorder keeps the end caps perfectly circular at
        // any height, so the controls match the ambience bar above them and
        // never read as a lopsided rounded rectangle.
        decoration: ShapeDecoration(
          color: bg,
          shape: StadiumBorder(side: BorderSide(color: border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(OmIcons.byName(icon), size: 19, color: fg),
            const SizedBox(width: 8),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontSize: 17, fontWeight: FontWeight.w700, color: fg),
            ),
          ],
        ),
      ),
    );
  }
}
