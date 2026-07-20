import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/focus_mode.dart';
import '../../providers/focus_provider.dart';
import '../../providers/task_provider.dart';
import '../../widgets/om_button.dart';
import '../../widgets/om_switch.dart';
import '../../widgets/om_tappable.dart';
import '../../widgets/om_top_bar.dart';
import 'body_doubling_screen.dart';
import 'focus_help.dart';

/// "focus" - pick a mode (Sprint/Pomodoro/Deep Work/Flow) and optionally turn
/// on body doubling. The active timer screen lands in a later pass.
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

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.screenTop, AppSpacing.screenH, AppSpacing.screenBottom),
      children: [
        const OmTopBar(title: 'focus', subtitle: "what's the vibe right now?"),
        const _CurrentTaskCard(),
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
          onPressed: () {
            Haptics.medium();
            final mode = _mode;
            if (_bodyDoubling) {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => BodyDoublingScreen(autoStart: true, mode: mode)),
              );
            } else {
              context.read<FocusProvider>().start(mode, false);
            }
          },
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

/// Live "current task" pulled from the schedule (the next un-done block), so the
/// focus screen reflects what's actually up rather than a placeholder.
class _CurrentTaskCard extends StatelessWidget {
  const _CurrentTaskCard();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final task = context.watch<TaskProvider>().upNext;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
        border: Border.all(color: c.border.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: c.primaryTint, borderRadius: BorderRadius.circular(12)),
            child: Icon(OmIcons.byName('target'), size: 18, color: c.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CURRENT TASK',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: c.text2,
                          fontSize: 9,
                          letterSpacing: 1,
                          fontWeight: FontWeight.w800,
                        )),
                const SizedBox(height: 2),
                Text(
                  task?.title ?? 'nothing scheduled - pick a mode and just begin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ],
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

