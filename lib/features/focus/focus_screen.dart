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
  /// Pomodoro's 25 minutes is the sane default to open on.
  int _minutes = 25;
  String _label = 'Pomodoro';
  bool _bodyDoubling = false;

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
    super.dispose();
  }

  /// The mode actually started: a preset when the chosen length still matches
  /// one, otherwise a custom session at whatever length was set.
  FocusMode get _mode {
    for (final preset in FocusMode.presets) {
      if (preset.minutes == _minutes) return preset;
    }
    return FocusMode(name: 'Focus', minutes: _minutes, iconName: 'timer', when: 'your call');
  }

  /// True when the length is not one of the four named ones, which is what the
  /// "custom" chip shows and stays lit for.
  bool get _isCustom => !FocusMode.presets.any((m) => m.minutes == _minutes);

  /// Set the length, and the name that goes with it.
  ///
  /// This used to animate a PageController that no longer had a PageView under
  /// it (the swipe dial was replaced by chips) and never touched [_minutes] at
  /// all, so every chip on the row was dead: the screen was stuck on 25m and a
  /// tap threw on the unattached controller.
  void _selectMinutes(int minutes, String label) {
    Haptics.select();
    setState(() {
      _minutes = minutes;
      _label = label;
    });
  }

  /// The way to any length that is not one of the four. Behind one chip rather
  /// than spread across eighteen more: see the note on the row itself.
  Future<void> _pickCustomLength() async {
    Haptics.light();
    var minutes = _minutes;
    final chosen = await showOmFormPage<int>(
      context,
      title: 'how long',
      subtitle: 'drag the dial, or tap either side of it',
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OmMinuteDial(
              value: minutes,
              max: 360,
              onChanged: (m) => setSheetState(() => minutes = m),
            ),
            const SizedBox(height: AppSpacing.xl),
            OmButton(
              label: 'use this',
              onPressed: () => Navigator.of(builderContext).pop(minutes),
            ),
          ],
        ),
      ),
    );
    if (chosen != null && mounted) _selectMinutes(chosen, 'Focus');
  }

  /// The scene's own name, or null when there is none. Shown on the start
  /// card so the summary never hides a setting that will change the session.
  String? get _sceneLabel =>
      _sceneId == 'none' ? null : ambienceById(_sceneId).label;

  /// Every decision this screen used to stack down the page, in one sheet.
  ///
  /// The controls are the originals, unchanged: the 2x2 length grid, the
  /// custom tile, the scene wrap and the body doubling row were each already
  /// carefully worked out (see the notes on their own classes) and the problem
  /// was never any one of them. It was that all four were on the main screen
  /// at once with the start button underneath. Moving them here keeps every
  /// capability and gives the page back its purpose.
  ///
  /// State stays on the screen rather than in the sheet, so a change applies
  /// the moment it is made and survives the sheet being dismissed by a swipe.
  /// The sheet gets its own setState so it repaints too, since both are
  /// showing the same four values.
  Future<void> _openSessionOptions() async {
    Haptics.light();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (builderContext, setSheetState) {
          final c = builderContext.omColors;
          void both(VoidCallback fn) {
            setState(fn);
            setSheetState(() {});
          }

          return Container(
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, AppSpacing.md,
                AppSpacing.screenH, AppSpacing.xl),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Row(
                    children: [
                      Text('how long',
                          style: Theme.of(builderContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 16)),
                      const Spacer(),
                      Flexible(
                        child: Text('${_minutes}m · ${_label.toLowerCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: Theme.of(builderContext)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                    color: c.primary, fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (var row = 0; row < 2; row++) ...[
                    if (row > 0) const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        for (var col = 0; col < 2; col++) ...[
                          if (col > 0) const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Builder(builder: (_) {
                              final mode = FocusMode.presets[row * 2 + col];
                              return _LengthTile(
                                mode: mode,
                                selected: _minutes == mode.minutes,
                                onTap: () => both(() {
                                  Haptics.select();
                                  _minutes = mode.minutes;
                                  _label = mode.name;
                                }),
                              );
                            }),
                          ),
                        ],
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _CustomLengthTile(
                    minutes: _isCustom ? _minutes : null,
                    selected: _isCustom,
                    onTap: () async {
                      await _pickCustomLength();
                      setSheetState(() {});
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  Row(
                    children: [
                      Text('scene',
                          style: Theme.of(builderContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontSize: 16)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('sets the mood while you focus',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(builderContext)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: c.text2)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      for (final scene in kFocusAmbiences)
                        _AmbientChip(
                          label: scene.label,
                          icon: scene.icon,
                          selected: _sceneId == scene.id,
                          onTap: () => both(() {
                            Haptics.select();
                            _sceneId = scene.id;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _BodyDoublingRow(
                    enabled: _bodyDoubling,
                    onToggle: (v) => both(() => _bodyDoubling = v),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  OmButton(
                    label: 'done',
                    onPressed: () => Navigator.of(builderContext).pop(),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
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

        // The block you are already in, if there is one. Above the generic
        // starter because it needs no decisions at all: the length, the name
        // and the reason are already known, so it is the shortest path from
        // opening this screen to actually working.
        _NowCard(
          task: current ?? next,
          isNow: current != null,
          onFocus: () => _focusOnTask((current ?? next)!),
        ),
        const SizedBox(height: AppSpacing.xl),

        // Starting is now the first thing on the screen rather than the last.
        //
        // This page used to stack five full-width configuration sections -
        // length, scene, body doubling, each with its own heading - and put
        // the start button underneath all of them. Every one of those sections
        // was individually well made, which is exactly how the screen ended up
        // a wall: nothing was bad enough to cut, so all of it stayed, and the
        // one thing the page exists for sat below the fold behind a scroll.
        //
        // So the decisions are folded into one sheet behind the summary line,
        // and the screen asks one question instead of four. The defaults are
        // good (25 minutes, no scene, no body doubling), so the common path is
        // open the tab, press start. Nothing was removed: every control is one
        // tap away in [_openSessionOptions], and the summary names the current
        // setting so the card never hides what it is about to do.
        _StartCard(
          minutes: _minutes,
          label: _label,
          sceneLabel: _sceneLabel,
          bodyDoubling: _bodyDoubling,
          onOptions: _openSessionOptions,
          onStart: () => _startSession(_mode),
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
        const SizedBox(height: AppSpacing.lg),

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

/// The one thing this screen is for: start focusing.
///
/// Two parts, in the order the decision is actually made. The summary line on
/// top states what is about to happen in plain words ("25 min · Pomodoro ·
/// rain") and opens the options sheet when tapped, so the settings are
/// visible without being laid out across the page. The button underneath
/// starts it.
///
/// The summary is the whole reason the configuration could move off-screen
/// without the page becoming vague: it always names the current length, the
/// scene and whether body doubling is on, so nothing the sheet holds can take
/// effect invisibly. A collapsed control that hides its own state is worse
/// than the wall of sections this replaced.
class _StartCard extends StatelessWidget {
  const _StartCard({
    required this.minutes,
    required this.label,
    required this.sceneLabel,
    required this.bodyDoubling,
    required this.onOptions,
    required this.onStart,
  });

  final int minutes;
  final String label;
  final String? sceneLabel;
  final bool bodyDoubling;
  final VoidCallback onOptions;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    // Only what is actually set. A summary that always said "no scene, no
    // body doubling" would be noise on the common path.
    final extras = <String>[
      if (sceneLabel != null) sceneLabel!,
      if (bodyDoubling) 'body doubling',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OmTappable(
            onTap: onOptions,
            feedback: OmTapFeedback.none,
            pressedScale: 0.99,
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text('$minutes',
                              style: t.displaySmall?.copyWith(
                                  fontWeight: FontWeight.w800, height: 1)),
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text('min',
                                style: t.titleMedium?.copyWith(color: c.text2)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        extras.isEmpty
                            ? label.toLowerCase()
                            : '${label.toLowerCase()} · ${extras.join(' · ')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.bodySmall?.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Named, not just a chevron: "change" says the number above is
                // editable, which an icon alone leaves people to guess.
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('change',
                        style: t.labelMedium?.copyWith(
                            color: c.primary, fontWeight: FontWeight.w700)),
                    Icon(Icons.chevron_right_rounded, size: 18, color: c.primary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          OmButton(
            label: 'start ${label.toLowerCase()} · ${minutes}m',
            onPressed: onStart,
          ),
        ],
      ),
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
    // Deeper in the dark than in the light.
    //
    // 0.62 of the way to black from a light periwinkle is #3C3D5A, which on a
    // pale page is a handsome dark slab and on a near-black page is a bright
    // purple block - 1.75:1 against the page, bright enough to be the first
    // thing the eye lands on and the loudest thing on the screen. At 0.74 it
    // is #292A3D: still clearly its own object at 1.31:1, charcoal with the
    // brand in it rather than a panel of colour, and white on it goes from
    // 10.46:1 to 14.07:1.
    final darkInk =
        Color.lerp(c.primary, Colors.black, context.isDark ? 0.74 : 0.62)!;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            // A 30px blur of brand colour at 0.34 is not a shadow on a dark
            // page, it is a glow around the card. Dropped well below the light
            // value: the card is already separated from the page by its own
            // fill there, so the shadow only has to hint at a lift.
            color: c.primary.withValues(alpha: context.isDark ? 0.16 : 0.24),
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
                  // Flat in dark, a soft sweep in light.
                  //
                  // The sweep exists to lift a dark card off a pale page. On a
                  // near-black page it has nothing to lift off, and a dark
                  // indigo fading into a darker one is just a muddy patch with
                  // a seam down it. The card already separates from the page by
                  // being lighter than it.
                  color: context.isDark ? darkInk : null,
                  gradient: context.isDark
                      ? null
                      : LinearGradient(
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
                              decoration: BoxDecoration(
                                color: c.success,
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
              // Solid: a 34px circle cannot show a gradient, only a smudge.
              decoration:
                  BoxDecoration(color: c.brandSolid, shape: BoxShape.circle),
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

/// One of the four named lengths, as a tile.
///
/// The name leads, the number sits under it, and the preset's own "use it
/// when" line - which the model has always carried and the UI has never shown -
/// goes underneath that. As a pill there was room for none of it, which is
/// what made a row of them read as a row of numbers.
class _LengthTile extends StatelessWidget {
  const _LengthTile({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final FocusMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // A selected tile is filled with the brand indigo, not with c.primary.
    //
    // c.primary is the light periwinkle in dark mode, so white on it measured
    // 2.40:1: the tile you had just chosen was the one you could no longer
    // read. It was marginal in light mode too, at 4.39:1. brandSolid is the
    // deep end of the brand in both themes, which white clears at 4.80:1 and
    // 4.78:1 - and it is the same fill the coach's own bubbles use, so a
    // chosen thing looks chosen the same way everywhere.
    final ink = selected ? OmColors.onFill(c.brandSolid) : c.text;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.97,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected ? c.brandSolid : c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? c.brandSolid : c.border.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(OmIcons.byName(mode.iconName),
                    size: 17, color: selected ? ink : c.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    mode.name.toLowerCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 15),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${mode.minutes} min',
              style: TextStyle(
                  color: ink,
                  fontWeight: FontWeight.w700,
                  fontSize: 19,
                  height: 1.0),
            ),
            const SizedBox(height: 3),
            Text(
              mode.when,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: selected
                        ? ink.withValues(alpha: 0.82)
                        : c.text2,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Any other length, as a full width row under the four.
class _CustomLengthTile extends StatelessWidget {
  const _CustomLengthTile({
    required this.minutes,
    required this.selected,
    required this.onTap,
  });

  /// Null until a custom length has actually been chosen, so the tile reads as
  /// a door before it has an answer behind it and as the answer afterwards.
  final int? minutes;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // A selected tile is filled with the brand indigo, not with c.primary.
    //
    // c.primary is the light periwinkle in dark mode, so white on it measured
    // 2.40:1: the tile you had just chosen was the one you could no longer
    // read. It was marginal in light mode too, at 4.39:1. brandSolid is the
    // deep end of the brand in both themes, which white clears at 4.80:1 and
    // 4.78:1 - and it is the same fill the coach's own bubbles use, so a
    // chosen thing looks chosen the same way everywhere.
    final ink = selected ? OmColors.onFill(c.brandSolid) : c.text;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? c.brandSolid : c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected ? c.brandSolid : c.border.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          children: [
            Icon(OmIcons.byName('sliders'),
                size: 17, color: selected ? ink : c.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                minutes == null ? 'custom' : 'custom  $minutes min',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: ink, fontWeight: FontWeight.w800, fontSize: 15),
              ),
            ),
            Icon(OmIcons.byName('chevR'),
                size: 16,
                color: selected ? ink : c.text2),
          ],
        ),
      ),
    );
  }
}

/// Body doubling: a switch, and when it is on, a line saying what happens next.
///
/// It used to carry a picker for the "room" you sat in - café, library, rain,
/// silence. That picker was a prop. The chosen room was held in a field on the
/// screen, used to decide which chip looked selected, and then dropped on the
/// floor: BodyDoublingScreen takes an auto-start flag and a mode, and has never
/// had anywhere to put a room. So it was four choices that changed nothing,
/// and two of its four words - "café" and "rain" - were also scenes in the
/// picker directly above it, where they did do something. Asking someone to
/// choose twice between the same two words, and honouring neither answer, is
/// worse than not asking.
class _BodyDoublingRow extends StatelessWidget {
  const _BodyDoublingRow({required this.enabled, required this.onToggle});

  final bool enabled;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The status line sits under the title rather than beside it, and that
        // is what stops the switch sliding.
        //
        // It used to be a Flexible next to an Expanded. Both default to flex 1,
        // so the row split its free space between them by flex rather than by
        // content: the loose Flexible took only what its text needed and handed
        // the rest back, and with the row packed from the start that slack
        // ended up *after* the switch. Toggling replaced "work alongside
        // someone" with "on", the slack grew by the difference, and the switch
        // visibly jumped left on its own tap.
        //
        // Nothing in this row changes width now, so there is nothing to move.
        Row(
          children: [
            Icon(OmIcons.byName('users'),
                size: 18, color: enabled ? c.primary : c.text2),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('body doubling',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontSize: 15.5)),
                  const SizedBox(height: 2),
                  Text(
                    'work alongside someone',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: c.text2),
                  ),
                ],
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
                  child: Text(
                    'we will match you with someone focusing right now, and '
                    'keep looking in the background if nobody is free yet.',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: c.text2, height: 1.45),
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
    // Same reason as the length tiles.
    final ink = selected ? OmColors.onFill(c.brandSolid) : c.text;
    return OmTappable(
      onTap: onTap,
      pressedScale: 0.95,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? c.brandSolid : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: selected ? c.brandSolid : c.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(OmIcons.byName(icon), size: 15, color: selected ? ink : c.text2),
            const SizedBox(width: 6),
            Text(label.toLowerCase(),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: ink,
                      fontWeight: FontWeight.w600,
                    )),
          ],
        ),
      ),
    );
  }
}
