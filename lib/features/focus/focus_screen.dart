import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/task_icon.dart';
import '../../core/utils/toast.dart';
import '../../models/focus_ambience.dart';
import '../../models/focus_mode.dart';
import '../../models/saved_focus.dart';
import '../../models/task.dart';
import '../../providers/focus_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_button.dart';
import '../../widgets/om_form_page.dart';
import '../../widgets/om_minute_dial.dart';
import '../../widgets/om_glass.dart';
import '../../widgets/om_tappable.dart';
import '../../widgets/text_editing_scope.dart';
import 'body_doubling_screen.dart';
import 'focus_help.dart';

/// "focus" - opens on who you are and what is happening right now, then offers
/// the ways in: the block you are already in, a focus you saved, or a fresh
/// session off the dial.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  /// Minute options the dial snaps through: fine-grained where short sessions
  /// live, coarser once you are past an hour.
  static const _steps = [
    5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, //
    75, 90, 105, 120, 150, 180, 210, 240, 300, 360,
  ];

  late final PageController _dial = PageController(
    // Pomodoro's 25 minutes is the sane default to open on.
    initialPage: _steps.indexOf(25),
    viewportFraction: 0.26,
  );

  int _minutes = 25;
  String _label = 'Pomodoro';
  bool _bodyDoubling = false;
  String _ambient = 'Café';

  /// The background scene (looping video) the session runs inside. 'none' keeps
  /// the plain screen.
  String _sceneId = 'none';

  /// The "now" card counts down between rebuilds, so it needs its own pulse.
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    _dial.dispose();
    super.dispose();
  }

  /// The mode actually started: a preset when the dial still matches one,
  /// otherwise a custom session at whatever the dial says.
  FocusMode get _mode {
    for (final preset in FocusMode.presets) {
      if (preset.minutes == _minutes) return preset;
    }
    return FocusMode(name: 'Focus', minutes: _minutes, iconName: 'timer', when: 'your call');
  }

  void _selectMinutes(int minutes) {
    final index = _steps.indexOf(minutes);
    if (index == -1) return;
    Haptics.select();
    _dial.animateToPage(index, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
  }

  /// Start a session, honouring body doubling either way.
  void _startSession(FocusMode mode, {String? taskTitle, int? seconds}) {
    Haptics.medium();
    if (_bodyDoubling) {
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => BodyDoublingScreen(autoStart: true, mode: mode)),
      );
      return;
    }
    context.read<FocusProvider>().start(mode, false,
        taskTitle: taskTitle, seconds: seconds, ambienceId: _sceneId);
  }

  /// "Focus on this task": the timer runs the block's *remaining* time, so a
  /// two-hour block entered forty minutes late starts at 1:20:00, not 2:00:00.
  void _focusOnTask(Task task) {
    final now = DateTime.now();
    final end = task.endTime;
    final start = task.startTime;
    var remaining = end != null && end.isAfter(now) && start != null && !start.isAfter(now)
        ? end.difference(now)
        : (task.duration ?? const Duration(minutes: 25));
    if (remaining < const Duration(minutes: 1)) remaining = const Duration(minutes: 1);

    _startSession(
      FocusMode(
        name: task.title,
        minutes: (remaining.inSeconds / 60).ceil(),
        iconName: 'target',
        when: 'from your schedule',
      ),
      taskTitle: task.title,
      seconds: remaining.inSeconds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tasks = context.watch<TaskProvider>();
    final current = tasks.nowBlock;
    final next = current == null ? tasks.nextBlock : null;
    final saved = context.watch<FocusProvider>().savedFocuses;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.screenTop, AppSpacing.screenH, AppSpacing.screenBottom),
      children: [
        const _FocusGreeting(),
        const SizedBox(height: AppSpacing.lg),

        _NowCard(
          task: current ?? next,
          isNow: current != null,
          onFocus: () => _focusOnTask((current ?? next)!),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Saved focuses: the named things you keep coming back to.
        Row(
          children: [
            Text('your focuses', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16)),
            const Spacer(),
            if (saved.isNotEmpty)
              Text('hold to remove',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 150,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              // The create tile leads, so it's always one tap away no matter how
              // many saved focuses pile up to its right.
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: _NewFocusCard(
                  onTap: () => showNewFocusSheet(
                    context,
                    initialMinutes: _minutes,
                    onStart: (name, minutes) => _startSession(
                      FocusMode(name: name, minutes: minutes, iconName: 'target', when: 'saved by you'),
                      taskTitle: name,
                    ),
                  ),
                ),
              ),
              for (final focus in saved)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _SavedFocusCard(
                    focus: focus,
                    onTap: () => _startSession(
                      FocusMode(
                        name: focus.name,
                        minutes: focus.minutes,
                        iconName: focus.iconName,
                        when: 'saved by you',
                      ),
                      taskTitle: focus.name,
                    ),
                    onRemove: () {
                      Haptics.medium();
                      context.read<FocusProvider>().removeSavedFocus(focus.id);
                      Toast.show(context, 'Removed "${focus.name}"');
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        // One control for one value.
        //
        // This was a 22-stop dial you swiped through, and *underneath it* a row
        // of named presets. Both set the same minutes. Two controls for one
        // number, stacked, took a third of the screen and made the page scroll
        // for no reason - and having set 45 on the dial, "Deep Work" below it
        // still looked unselected, so the screen contradicted itself.
        //
        // Now: the named lengths lead, because "how do I feel" is the easier
        // question, and the plain numbers follow for anyone who wants a
        // specific one. One row, one selected state, one source of truth.
        Row(
          children: [
            Text('how long',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16)),
            const Spacer(),
            // Flexible: the right hand side is the mode's own name, and a long
            // one ran off the edge of a narrow phone.
            Flexible(
              child: Text('${_minutes}m · ${_label.toLowerCase()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: c.primary, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 58,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              for (final mode in FocusMode.presets)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _LengthChip(
                    label: mode.name.toLowerCase(),
                    minutes: mode.minutes,
                    icon: mode.iconName,
                    selected: _minutes == mode.minutes,
                    onTap: () => _selectMinutes(mode.minutes),
                  ),
                ),
              for (final value in _steps)
                if (!FocusMode.presets.any((m) => m.minutes == value))
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _LengthChip(
                      minutes: value,
                      selected: _minutes == value,
                      onTap: () => _selectMinutes(value),
                    ),
                  ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Scene: the looping backdrop the running timer sits inside.
        Row(
          children: [
            Text('scene',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16)),
            const SizedBox(width: 8),
            Flexible(
              child: Text('sets the mood while you focus',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: c.text2)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 46,
          child: ListView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            children: [
              for (final scene in kFocusAmbiences)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: _AmbientChip(
                    label: scene.label,
                    icon: scene.icon,
                    selected: _sceneId == scene.id,
                    onTap: () {
                      Haptics.select();
                      setState(() => _sceneId = scene.id);
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // Body doubling belongs with the scene: both are "what is it like while
        // I work", both are optional, and neither is the decision this screen
        // is for. It used to be a full card at the very bottom, which put the
        // least important choice in the most prominent place and pushed the
        // start button off the fold.
        _BodyDoublingRow(
          enabled: _bodyDoubling,
          ambient: _ambient,
          onToggle: (v) => setState(() => _bodyDoubling = v),
          onAmbient: (name) => setState(() => _ambient = name),
        ),
        const SizedBox(height: AppSpacing.lg),
        OmButton(
          label: 'start ${_label.toLowerCase()} · ${_minutes}m',
          onPressed: () => _startSession(_mode),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: OmTappable(
            onTap: () => askMyndForHelp(context),
            feedback: OmTapFeedback.light,
            pressedScale: 0.96,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(OmIcons.byName('life-buoy'), size: 16, color: c.primary),
                  const SizedBox(width: 6),
                  // Flexible even though the Row is min-sized: min means "as
                  // narrow as the children", not "as wide as you like", and
                  // when the surrounding column is tight this line is the one
                  // that does not fit.
                  Flexible(
                    child: Text('Need help? Talk to Mynd',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: c.primary,
                                  fontWeight: FontWeight.w700,
                                )),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// "good morning, <you>" over a soft brand wash, with the day's real numbers
/// underneath - nothing invented, just what the schedule already knows.
class _FocusGreeting extends StatelessWidget {
  const _FocusGreeting();

  static String _greetingFor(int hour) {
    if (hour < 12) return 'good morning,';
    if (hour < 17) return 'good afternoon,';
    return 'good evening,';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final name = ApiConfig.instance.displayName ?? 'friend';
    final stats = context.watch<TaskProvider>().statsFor(DateTime.now());
    // Real seconds on the clock, not the sum of the durations of whatever was
    // ticked off. Those are very different numbers and only one of them is true.
    final focused = context.watch<FocusProvider>().focusedToday;
    final focusedLabel = focused.inMinutes >= 60
        ? '${focused.inHours}h ${focused.inMinutes % 60}m focused'
        : '${focused.inMinutes}m focused';

    // A single dark, premium hero: the greeting and a live orb up top, two
    // connected stat tiles below, all on one brand-lit slab so the top of the
    // screen reads as one designed object rather than a plain card.
    final darkInk = Color.lerp(c.primary, Colors.black, 0.62)!;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: context.isDark ? 0.34 : 0.24),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(darkInk, c.primary, 0.28)!,
                      darkInk,
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _greetingFor(DateTime.now().hour),
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: Colors.white.withValues(alpha: 0.72),
                                    letterSpacing: -0.2,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    fontSize: 27,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: -0.6,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "let's get you locked in.",
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.66),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  // Two connected stat tiles sharing one translucent bar.
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: [
                        _HeroStat(icon: 'check', value: '${stats.done}', label: 'done today'),
                        Container(width: 1, height: 34, color: Colors.white.withValues(alpha: 0.14)),
                        _HeroStat(icon: 'timer', value: focusedLabel.replaceAll(' focused', ''), label: 'focused'),
                      ],
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

/// One half of the hero's stat bar: an icon, a big number, a quiet label.
class _HeroStat extends StatelessWidget {
  const _HeroStat({required this.icon, required this.value, required this.label});

  final String icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        child: Row(
          children: [
            Icon(OmIcons.byName(icon), size: 18, color: Colors.white.withValues(alpha: 0.9)),
            const SizedBox(width: 10),
            // Expanded, and the label clipped rather than allowed to size the
            // row. Two of these share the width of the phone, so the longest
            // wording ("3h 20m focused") decides whether the card fits, and on
            // a 320pt screen it did not.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 20,
                            height: 1,
                          )),
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.6),
                          )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What is on the clock right now (or next), with the one button that matters.
class _NowCard extends StatelessWidget {
  const _NowCard({required this.task, required this.isNow, required this.onFocus});

  final Task? task;
  final bool isNow;
  final VoidCallback onFocus;

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'am' : 'pm'}';
  }

  static String _left(Duration d) {
    if (d.inMinutes >= 60) return '${d.inHours}h ${d.inMinutes % 60}m left';
    return '${d.inMinutes < 1 ? 1 : d.inMinutes}m left';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = task;

    if (t == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.border),
        ),
        child: Row(
          children: [
            Icon(OmIcons.byName('calendar'), size: 18, color: c.text2),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'nothing scheduled right now - pick a length below and just begin',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2),
              ),
            ),
          ],
        ),
      );
    }

    final now = DateTime.now();
    final end = t.endTime;
    final remaining = isNow && end != null ? end.difference(now) : (t.duration ?? const Duration(minutes: 25));

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: context.isDark ? 0.4 : 0.09),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: OmGlass(
        borderRadius: 24,
        blur: 24,
        opacity: context.isDark ? 0.4 : 0.8,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: c.primaryTint,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(taskIcon(t.title), size: 20, color: c.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (isNow) ...[
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF22C55E),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Text(
                            isNow ? 'HAPPENING NOW' : 'UP NEXT',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: isNow ? c.primary : c.text2,
                                  fontSize: 9,
                                  letterSpacing: 1,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        t.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontSize: 16.5,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        t.startTime == null || end == null
                            ? _left(remaining)
                            : '${_clock(t.startTime!)} - ${_clock(end)} · ${_left(remaining)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OmButton(
              label: isNow ? 'focus on this task' : 'start this early',
              onPressed: onFocus,
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved focus: minutes lead, the name says what it is, the disc says "go".
class _SavedFocusCard extends StatelessWidget {
  const _SavedFocusCard({required this.focus, required this.onTap, required this.onRemove});

  final SavedFocus focus;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      onLongPress: onRemove,
      feedback: OmTapFeedback.light,
      pressedScale: 0.96,
      child: Container(
        width: 156,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: context.isDark ? 0.35 : 0.07),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Three-digit lengths and large text scales must not push the
                // "go" disc off the card, so the number gives way first.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${focus.minutes}',
                          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                color: c.primary,
                                height: 1.05,
                              ),
                        ),
                        const SizedBox(width: 3),
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text('min',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
                  child: Icon(Icons.arrow_outward_rounded, size: 15, color: c.primary),
                ),
              ],
            ),
            const Spacer(),
            Icon(taskIcon(focus.name), size: 15, color: c.text2),
            const SizedBox(height: 6),
            Text(
              focus.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13.5, height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}

/// The dashed "+ new focus" tile that closes the row.
class _NewFocusCard extends StatelessWidget {
  const _NewFocusCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      pressedScale: 0.96,
      child: Container(
        width: 132,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: c.primaryTint.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: c.primary.withValues(alpha: 0.35)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(gradient: c.brandGradient, shape: BoxShape.circle),
              child: const Icon(Icons.add_rounded, size: 20, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text('new focus',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 14)),
            const SizedBox(height: 2),
            Text('name it, keep it',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
          ],
        ),
      ),
    );
  }
}

/// "New focus": name the thing, choose how long, keep it for next time.
Future<void> showNewFocusSheet(
  BuildContext context, {
  required int initialMinutes,
  required void Function(String name, int minutes) onStart,
}) async {
  // Snapped to 5, so any length is reachable. The old fixed set of ten presets
  // made the machine's convenient numbers the only allowed answers.
  var minutes = initialMinutes.clamp(5, 360);
  final focus = context.read<FocusProvider>();

  await showOmFormPage<void>(
    context,
    title: 'new focus',
    subtitle: 'what are you sitting down to do?',
    builder: (sheetContext) {
      final c = sheetContext.omColors;
      return TextEditingScope(
        builder: (scopeContext, controller) => Builder(
          builder: (_) => StatefulBuilder(
            builder: (builderContext, setSheetState) {
              void save({required bool startNow}) {
                final name = controller.text.trim();
                if (name.isEmpty) {
                  Toast.show(context, 'Give this focus a name first');
                  return;
                }
                focus.addSavedFocus(name: name, minutes: minutes);
                FocusManager.instance.primaryFocus?.unfocus();
                Navigator.of(builderContext).pop();
                Haptics.success();
                if (startNow) {
                  onStart(name, minutes);
                } else {
                  Toast.show(context, 'Saved "$name"');
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: controller,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    style: Theme.of(builderContext).textTheme.titleMedium?.copyWith(fontSize: 17),
                    decoration: InputDecoration(
                      hintText: 'read atomic habits',
                      filled: true,
                      fillColor: c.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('HOW LONG',
                      style: Theme.of(builderContext).textTheme.labelSmall?.copyWith(
                            color: c.text2,
                            fontSize: 9,
                            letterSpacing: 1,
                            fontWeight: FontWeight.w800,
                          )),
                  OmMinuteDial(
                    value: minutes,
                    max: 360,
                    onChanged: (m) => setSheetState(() => minutes = m),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  OmButton(label: 'save and start', onPressed: () => save(startNow: true)),
                  const SizedBox(height: AppSpacing.sm),
                  Center(
                    child: OmTappable(
                      onTap: () => save(startNow: false),
                      feedback: OmTapFeedback.light,
                      pressedScale: 0.96,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                        child: Text('just save it for later',
                            style: Theme.of(builderContext).textTheme.labelMedium?.copyWith(
                                  color: c.text2,
                                  fontWeight: FontWeight.w700,
                                )),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}

/// A professional body-doubling control: a clean switch row (no checkmarks) and,
/// when on, a soft explanation that we'll match the user with someone currently
/// focusing - or keep searching in the background - plus an ambience selector.
/// One length. Named ones carry their name, the rest carry their number.
///
/// The same chip for both, so a preset and a plain length cannot look like two
/// different kinds of thing when they set exactly the same value.
class _LengthChip extends StatelessWidget {
  const _LengthChip({
    required this.minutes,
    required this.selected,
    required this.onTap,
    this.label,
    this.icon,
  });

  final int minutes;
  final bool selected;
  final VoidCallback onTap;
  final String? label;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: label == null ? 18 : 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? c.primary : c.border.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(OmIcons.byName(icon!),
                  size: 15, color: selected ? Colors.white : c.text2),
              const SizedBox(width: 7),
            ],
            Text(
              label == null ? '${minutes}m' : '$label  ${minutes}m',
              style: TextStyle(
                color: selected ? Colors.white : c.text,
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Body doubling, as one row rather than a slab.
///
/// The toggle is the whole decision. The ambience picker only appears once it
/// is on, because choosing a room to sit in is meaningless until you have said
/// you want to sit with anyone.
class _BodyDoublingRow extends StatelessWidget {
  const _BodyDoublingRow({
    required this.enabled,
    required this.ambient,
    required this.onToggle,
    required this.onAmbient,
  });

  final bool enabled;
  final String ambient;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onAmbient;

  static const _rooms = ['Café', 'Library', 'Rain', 'Silence'];

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(OmIcons.byName('users'),
                size: 18, color: enabled ? c.primary : c.text2),
            const SizedBox(width: 10),
            Expanded(
              child: Text('body doubling',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontSize: 15.5)),
            ),
            // Flexible, because this label and the title are both variable
            // width and the switch beside them is not. On a narrow phone an
            // unbounded Text here is an overflow waiting for a longer word.
            Flexible(
              child: Text(
                enabled ? 'on' : 'work alongside someone',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: c.text2),
              ),
            ),
            const SizedBox(width: 8),
            Switch.adaptive(
              value: enabled,
              activeTrackColor: c.primary,
              onChanged: (v) {
                Haptics.select();
                onToggle(v);
              },
            ),
          ],
        ),
        // Collapses to nothing when off, so the screen does not reserve space
        // for a choice that is not being offered.
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: enabled
              ? Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  // Wrap, not Row. Four chips of icon plus word do not fit
                  // across a phone, and a Row cannot do anything about that
                  // except paint the overflow stripes over the screen. Wrapping
                  // to a second line is the honest answer: every room stays
                  // reachable, which a horizontal scroll would not guarantee
                  // since nothing about it says there is more to the right.
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final room in _rooms)
                        _AmbientChip(
                          label: room,
                          icon: room == 'Café'
                              ? 'coffee'
                              : room == 'Library'
                                  ? 'book'
                                  : room == 'Rain'
                                      ? 'cloud-rain'
                                      : 'moon',
                          selected: ambient == room,
                          onTap: () {
                            Haptics.select();
                            onAmbient(room);
                          },
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}

/// A soft selectable ambience chip - highlighted by fill/border, no checkmark.
class _AmbientChip extends StatelessWidget {
  const _AmbientChip({required this.label, required this.icon, required this.selected, required this.onTap});

  final String label;
  final String icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      pressedScale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? c.primary : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(OmIcons.byName(icon), size: 15, color: selected ? Colors.white : c.text2),
            const SizedBox(width: 6),
            Text(label.toLowerCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? Colors.white : c.text,
                      fontWeight: FontWeight.w600,
                    )),
          ],
        ),
      ),
    );
  }
}
