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

/// "focus" — pick a mode (Sprint/Pomodoro/Deep Work/Flow) and optionally turn
/// on body doubling. The active timer screen lands in a later pass.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  FocusMode _selected = FocusMode.presets[1]; // Pomodoro
  bool _bodyDoubling = false;
  String _ambient = 'Café';

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.screenTop, AppSpacing.screenH, AppSpacing.screenBottom),
      children: [
        const OmTopBar(title: 'focus', subtitle: "what's the vibe right now?"),
        const _CurrentTaskCard(),
        const SizedBox(height: AppSpacing.lg),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.md,
          crossAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.25,
          children: [
            for (final mode in FocusMode.presets)
              _ModeCard(
                mode: mode,
                selected: _selected == mode,
                onTap: () {
                  Haptics.select();
                  setState(() => _selected = mode);
                },
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
          label: 'start ${_selected.name.toLowerCase()} · ${_selected.minutes}m',
          onPressed: () {
            Haptics.medium();
            if (_bodyDoubling) {
              Navigator.of(context, rootNavigator: true).push(
                MaterialPageRoute(builder: (_) => BodyDoublingScreen(autoStart: true, mode: _selected)),
              );
            } else {
              context.read<FocusProvider>().start(_selected, false);
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
                  task?.title ?? 'nothing scheduled — pick a mode and just begin',
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
/// focusing — or keep searching in the background — plus an ambience selector.
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
                      Text("we'll pair you with someone in a session — if no one's free yet, "
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

/// A soft selectable ambience chip — highlighted by fill/border, no checkmark.
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

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.selected, required this.onTap});

  final FocusMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
        decoration: BoxDecoration(
          color: selected ? c.primaryTint.withValues(alpha: 0.5) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: selected ? c.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              mainAxisSize: MainAxisSize.max,
              children: [
                Icon(OmIcons.byName(mode.iconName), color: c.text, size: 24),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(mode.name,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(color: c.text, fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 1),
                    Text('${mode.minutes} min',
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: c.text, fontWeight: FontWeight.w600, fontSize: 12)),
                    Text(mode.when,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: c.text2, fontSize: 10.5)),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
