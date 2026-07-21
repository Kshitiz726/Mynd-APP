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
import '../../models/focus_mode.dart';
import '../../models/saved_focus.dart';
import '../../models/task.dart';
import '../../providers/focus_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_button.dart';
import '../../widgets/om_form_page.dart';
import '../../widgets/om_minute_dial.dart';
import '../../widgets/om_glass.dart';
import '../../widgets/om_switch.dart';
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
  static const _steps = [5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 60, 75, 90, 105, 120];

  late final PageController _dial = PageController(
    // Pomodoro's 25 minutes is the sane default to open on.
    initialPage: _steps.indexOf(25),
    viewportFraction: 0.26,
  );

  int _minutes = 25;
  String _label = 'Pomodoro';
  bool _bodyDoubling = false;
  String _ambient = 'Café';

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
    context.read<FocusProvider>().start(mode, false, taskTitle: taskTitle, seconds: seconds);
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
              _NewFocusCard(
                onTap: () => showNewFocusSheet(
                  context,
                  initialMinutes: _minutes,
                  onStart: (name, minutes) => _startSession(
                    FocusMode(name: name, minutes: minutes, iconName: 'target', when: 'saved by you'),
                    taskTitle: name,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        Center(
          child: Text(
            'focus time in mins',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.text2),
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // The dial: the duration is the decision, so it gets the largest type on
        // the screen and a gesture of its own.
        SizedBox(
          height: 116,
          child: PageView.builder(
            controller: _dial,
            itemCount: _steps.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: (i) {
              Haptics.light();
              setState(() {
                _minutes = _steps[i];
                _label = FocusMode.presets
                        .where((m) => m.minutes == _steps[i])
                        .map((m) => m.name)
                        .firstOrNull ??
                    'Custom';
              });
            },
            itemBuilder: (context, i) {
              final value = _steps[i];
              final selected = value == _minutes;
              return Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  width: selected ? 96 : 66,
                  height: selected ? 96 : 66,
                  decoration: BoxDecoration(
                    gradient: selected ? c.brandGradient : null,
                    color: selected ? null : c.surfaceAlt,
                    borderRadius: BorderRadius.circular(selected ? 28 : 20),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: c.primary.withValues(alpha: 0.34),
                              blurRadius: 22,
                              offset: const Offset(0, 10),
                            ),
                          ]
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '$value',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: selected ? Colors.white : c.text2,
                          fontSize: selected ? 34 : 22,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            _label.toLowerCase(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(color: c.primary),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Presets stay: they are the "how do I feel" shortcut into the dial.
        Row(
          children: [
            for (final mode in FocusMode.presets)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _PresetChip(
                    mode: mode,
                    selected: _minutes == mode.minutes,
                    onTap: () => _selectMinutes(mode.minutes),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),

        _BodyDoublingTile(
          enabled: _bodyDoubling,
          ambient: _ambient,
          onToggle: (v) => setState(() => _bodyDoubling = v),
          onAmbient: (name) => setState(() => _ambient = name),
        ),
        const SizedBox(height: AppSpacing.xl),
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
                  Text('Need help? Talk to Mynd',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: c.primary,
                            fontWeight: FontWeight.w700,
                          )),
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
    final focused = stats.focused;
    final focusedLabel = focused.inMinutes >= 60
        ? '${focused.inHours}h ${focused.inMinutes % 60}m focused'
        : '${focused.inMinutes}m focused';

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: c.primary.withValues(alpha: context.isDark ? 0.28 : 0.16),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Stack(
          children: [
            // A brand glow in the corner, the way the reference lights its card.
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.1, -1.0),
                    radius: 1.4,
                    colors: [
                      c.primary.withValues(alpha: context.isDark ? 0.42 : 0.26),
                      c.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
            OmGlass(
              borderRadius: 28,
              blur: 26,
              opacity: context.isDark ? 0.34 : 0.62,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _greetingFor(DateTime.now().hour),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w500,
                          color: c.text2,
                          letterSpacing: -0.4,
                        ),
                  ),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.6,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Icon(OmIcons.byName('sparkles'), size: 14, color: c.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${stats.done} done today · $focusedLabel',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: c.text2,
                              ),
                        ),
                      ),
                    ],
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
  var minutes = initialMinutes.clamp(5, 180);
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
                      hintText: 'e.g. read atomic habits',
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

/// A preset shortcut: the minutes lead, the feeling explains.
class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.mode, required this.selected, required this.onTap});

  final FocusMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.94,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? c.primary.withValues(alpha: 0.5) : c.border),
        ),
        child: Column(
          children: [
            Icon(
              OmIcons.byName(mode.iconName),
              size: 18,
              color: selected ? c.primary : c.text2,
            ),
            const SizedBox(height: 6),
            Text(
              '${mode.minutes}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: selected ? c.primary : c.text,
                  ),
            ),
            Text(
              mode.name.toLowerCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: selected ? c.primary : c.text2,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A professional body-doubling control: a clean switch row (no checkmarks) and,
/// when on, a soft explanation that we'll match the user with someone currently
/// focusing - or keep searching in the background - plus an ambience selector.
class _BodyDoublingTile extends StatelessWidget {
  const _BodyDoublingTile({
    required this.enabled,
    required this.ambient,
    required this.onToggle,
    required this.onAmbient,
  });

  final bool enabled;
  final String ambient;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onAmbient;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: enabled ? c.primaryTint.withValues(alpha: 0.5) : c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: enabled ? c.primary.withValues(alpha: 0.4) : c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12)),
                child: Icon(OmIcons.byName('users'), size: 19, color: c.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('body doubling',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 16)),
                    const SizedBox(height: 2),
                    Text('focus alongside someone else who’s working right now',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              OmSwitch(value: enabled, onChanged: onToggle),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: enabled
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: AppSpacing.md),
                      Text("we'll pair you with someone in a session - if no one's free yet, "
                          'we keep matching quietly while your timer runs.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2)),
                      const SizedBox(height: AppSpacing.md),
                      Text('AMBIENCE',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: c.text2,
                                fontSize: 9,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w800,
                              )),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final (name, icon) in const [('Café', 'coffee'), ('Library', 'book'), ('Typing', 'keyboard')])
                            _AmbientChip(
                              label: name,
                              icon: icon,
                              selected: ambient == name,
                              onTap: () => onAmbient(name),
                            ),
                        ],
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
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
