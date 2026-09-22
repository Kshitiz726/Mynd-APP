import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../models/agent.dart';
import '../../providers/agent_provider.dart';
import '../../widgets/agent_avatar.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';

/// Tuning one agent.
///
/// Per agent, deliberately: these are not app preferences, they are who this
/// character is, and the whole promise of the picker is that switching to Blitz
/// gets you Blitz rather than whatever you last set the sliders to.
///
/// The bottom of the screen shows the actual instruction lines the model will
/// be given. Not a mock reply - that would need a model call for every slider
/// nudge, and a made-up one would be a lie about what the settings do. Showing
/// the real instructions is both cheaper and more honest: you can see your
/// change land, word for word.
class AgentSettingsScreen extends StatefulWidget {
  const AgentSettingsScreen({super.key, required this.agent});

  final Agent agent;

  static Future<void> open(BuildContext context, Agent agent) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => AgentSettingsScreen(agent: agent),
        ),
      );

  @override
  State<AgentSettingsScreen> createState() => _AgentSettingsScreenState();
}

class _AgentSettingsScreenState extends State<AgentSettingsScreen> {
  late AgentSettings _s;
  late final TextEditingController _custom;

  @override
  void initState() {
    super.initState();
    _s = context.read<AgentProvider>().settingsFor(widget.agent);
    _custom = TextEditingController(text: _s.custom);
  }

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  /// Written through on every change rather than behind a Save button. There is
  /// no destructive edit here and no half-valid state, so a Save would only be
  /// a way to lose your work by backing out.
  void _set(AgentSettings next) {
    setState(() => _s = next);
    context.read<AgentProvider>().update(widget.agent, next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final a = widget.agent;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  8, AppSpacing.md, AppSpacing.screenH, 0),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(a.name,
                        style: t.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800)),
                  ),
                  OmTappable(
                    onTap: () {
                      Haptics.light();
                      context
                          .read<AgentProvider>()
                          .resetToDefaults(a);
                      setState(() {
                        _s = a.defaults;
                        _custom.text = a.defaults.custom;
                      });
                    },
                    feedback: OmTapFeedback.none,
                    child: Text('Reset',
                        style: TextStyle(
                            color: c.primary, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.lg,
                  AppSpacing.screenH,
                  AppSpacing.screenBottom,
                ),
                children: [
                  Center(
                    child: AgentAvatar(
                      agent: a,
                      size: 96,
                      mood: AgentMood.idle,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  _Section('mood today'),
                  Text(
                    'Changes the face and the writing together. The sliders '
                    'below are who ${a.name} is; this is the day they are '
                    'having.',
                    style: TextStyle(color: c.text2, height: 1.4, fontSize: 13),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final e in AgentEmotion.values)
                        _Chip(
                          label: '${e.glyph}  ${e.label}',
                          selected: _s.emotion == e,
                          accent: a.accent,
                          onTap: () {
                            Haptics.select();
                            _set(_s.copyWith(emotion: e));
                          },
                        ),
                    ],
                  ),

                  _Section('how ${a.name} talks'),
                  _Slider(
                    label: 'warmth',
                    left: 'matter of fact',
                    right: 'openly warm',
                    value: _s.warmth,
                    accent: a.accent,
                    onChanged: (v) => _set(_s.copyWith(warmth: v)),
                  ),
                  _Slider(
                    label: 'directness',
                    left: 'suggests',
                    right: 'says the thing',
                    value: _s.directness,
                    accent: a.accent,
                    onChanged: (v) => _set(_s.copyWith(directness: v)),
                  ),
                  _Slider(
                    label: 'humour',
                    left: 'straight',
                    right: 'jokes around',
                    value: _s.humour,
                    accent: a.accent,
                    onChanged: (v) => _set(_s.copyWith(humour: v)),
                  ),
                  _Slider(
                    label: 'energy',
                    left: 'low and steady',
                    right: 'gets you moving',
                    value: _s.energy,
                    accent: a.accent,
                    onChanged: (v) => _set(_s.copyWith(energy: v)),
                  ),

                  _Section('length'),
                  Row(
                    children: [
                      for (final v in Verbosity.values)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _Chip(
                              label: v.label,
                              selected: _s.verbosity == v,
                              accent: a.accent,
                              fill: true,
                              onTap: () {
                                Haptics.select();
                                _set(_s.copyWith(verbosity: v));
                              },
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(_s.verbosity.blurb,
                      style: TextStyle(color: c.text2, fontSize: 13)),

                  _Section('habits'),
                  _Switch(
                    label: 'Ends on a question',
                    blurb: 'Some people find it warm. Some find it relentless.',
                    value: _s.asksQuestions,
                    accent: a.accent,
                    onChanged: (v) => _set(_s.copyWith(asksQuestions: v)),
                  ),
                  _Switch(
                    label: 'Uses emoji',
                    blurb: 'At most one, and only where it helps.',
                    value: _s.emoji,
                    accent: a.accent,
                    onChanged: (v) => _set(_s.copyWith(emoji: v)),
                  ),

                  _Section('in your own words'),
                  Container(
                    decoration: BoxDecoration(
                      color: c.surface,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                      border:
                          Border.all(color: c.border.withValues(alpha: 0.7)),
                    ),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: TextField(
                      controller: _custom,
                      maxLines: null,
                      minLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      onChanged: (v) => _set(_s.copyWith(custom: v)),
                      style: t.bodyLarge?.copyWith(height: 1.45),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        hintText:
                            'Anything else? "Call me by my first name." '
                            '"Never tell me to just start." "Remind me to eat."',
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'This is added last, so it wins where it disagrees with a '
                    'slider.',
                    style: TextStyle(color: c.text2, fontSize: 13),
                  ),

                  _Section('what ${a.name} is actually told'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.control),
                    ),
                    child: Text(
                      _s.promptBlock,
                      style: TextStyle(
                        color: c.text2,
                        height: 1.55,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontFamilyFallback: const ['Menlo', 'Courier'],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Word for word, on top of who ${a.name} is. No preview to '
                    'second-guess: this is the instruction itself.',
                    style: TextStyle(color: c.text2, fontSize: 13, height: 1.4),
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

class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, AppSpacing.xxl, 2, AppSpacing.md),
      child: Text(
        title,
        style: TextStyle(
          color: c.text2,
          fontSize: 11,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.left,
    required this.right,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final String left;
  final String right;
  final double value;
  final Color accent;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: accent,
              inactiveTrackColor: accent.withValues(alpha: 0.18),
              thumbColor: accent,
              overlayColor: accent.withValues(alpha: 0.14),
              trackHeight: 4,
            ),
            child: Slider(
              value: value,
              // Five stops, matching the three prompt bands plus their edges.
              // A continuous slider would imply a precision the prompt does
              // not have.
              divisions: 4,
              onChanged: onChanged,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(left, style: TextStyle(color: c.text2, fontSize: 12.5)),
              Text(right, style: TextStyle(color: c.text2, fontSize: 12.5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.fill = false,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.95,
      child: Container(
        width: fill ? double.infinity : null,
        alignment: fill ? Alignment.center : null,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.16) : c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? c.text : c.text2,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.blurb,
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final String label;
  final String blurb;
  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(blurb,
                    style: TextStyle(color: c.text2, fontSize: 13, height: 1.3)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            activeTrackColor: accent,
            onChanged: (v) {
              Haptics.select();
              onChanged(v);
            },
          ),
        ],
      ),
    );
  }
}
