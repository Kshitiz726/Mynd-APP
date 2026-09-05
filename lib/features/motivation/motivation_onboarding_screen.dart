import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../models/motivation.dart';
import '../../providers/motivation_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/fluid_orb.dart';
import '../../widgets/om_tappable.dart';

/// Setting up daily motivation: the promise, the schedule, then the subjects.
///
/// Laid out from the reference design Anj supplied, in Mynd's palette rather
/// than its green: brand periwinkle for anything that commits, warm peach for
/// what is only selected. The orb stands in for the reference's stock
/// illustration because the app already has a signature object and dropping
/// somebody else's art next to it would read as two apps.
class MotivationOnboardingScreen extends StatefulWidget {
  const MotivationOnboardingScreen({super.key});

  @override
  State<MotivationOnboardingScreen> createState() =>
      _MotivationOnboardingScreenState();
}

class _MotivationOnboardingScreenState
    extends State<MotivationOnboardingScreen> {
  final _pages = PageController();
  int _page = 0;

  int _count = 10;
  int _start = 9 * 60;
  int _end = 22 * 60;
  final _picked = <MotivationCategory>{};

  @override
  void initState() {
    super.initState();
    final s = context.read<MotivationProvider>().settings;
    _count = s.count;
    _start = s.startMinutes;
    _end = s.endMinutes;
    _picked.addAll(s.categories);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _next() {
    Haptics.light();
    _pages.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _finish() async {
    Haptics.success();
    final p = context.read<MotivationProvider>();
    await p.save(p.settings.copyWith(
      count: _count,
      startMinutes: _start,
      endMinutes: _end,
      categories: _picked,
      onboarded: true,
    ));
    // Asked here rather than on the first page: by now somebody has said how
    // many they want and when, so the prompt arrives as the obvious next step
    // instead of as a demand from a screen they have not read yet.
    await NotificationService.instance.requestPermissions();
    await p.refresh(force: true);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _Progress(page: _page),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _page = i),
                // Driven by the buttons. A schedule somebody swiped past
                // without setting is a schedule they did not choose.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _Promise(onStart: _next),
                  _Schedule(
                    count: _count,
                    start: _start,
                    end: _end,
                    onCount: (v) => setState(() => _count = v),
                    onStart: (v) => setState(() => _start = v),
                    onEnd: (v) => setState(() => _end = v),
                    onContinue: _next,
                  ),
                  _Areas(
                    picked: _picked,
                    onToggle: (cat) => setState(() {
                      Haptics.select();
                      _picked.contains(cat)
                          ? _picked.remove(cat)
                          : _picked.add(cat);
                    }),
                    onFinish: _finish,
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

/// Three dots, so somebody knows this is short.
class _Progress extends StatelessWidget {
  const _Progress({required this.page});

  final int page;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == page ? 22 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == page ? c.primary : c.border,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
        ],
      ),
    );
  }
}

/// Screen one: what this is for.
class _Promise extends StatelessWidget {
  const _Promise({required this.onStart});

  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // The reference sets the first word of each line light and the second
    // heavy, which is what gives the stack its rhythm. Copied exactly, in the
    // app's own two text colours.
    const lines = [
      ('SELF', 'LOVE.'),
      ('SELF', 'CARE.'),
      ('SELF', 'GROWTH.'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xl),
      child: Column(
        children: [
          const Spacer(flex: 2),
          const FluidOrb(size: 168),
          const Spacer(flex: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (light, heavy) in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: '$light ',
                          style: TextStyle(
                              color: c.text2, fontWeight: FontWeight.w800),
                        ),
                        TextSpan(
                          text: heavy,
                          style: TextStyle(
                              color: c.text, fontWeight: FontWeight.w900),
                        ),
                      ]),
                      style: const TextStyle(fontSize: 34, letterSpacing: -0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'a few words a day, written for where you are and what you are '
              'working on.',
              style: TextStyle(fontSize: 14, height: 1.4, color: c.text2),
            ),
          ),
          const Spacer(),
          _Cta(label: 'Get Started', onTap: onStart),
        ],
      ),
    );
  }
}

/// Screen two: how many and between when.
class _Schedule extends StatelessWidget {
  const _Schedule({
    required this.count,
    required this.start,
    required this.end,
    required this.onCount,
    required this.onStart,
    required this.onEnd,
    required this.onContinue,
  });

  final int count;
  final int start;
  final int end;
  final ValueChanged<int> onCount;
  final ValueChanged<int> onStart;
  final ValueChanged<int> onEnd;
  final VoidCallback onContinue;

  /// Half-hour steps. Minute-accurate start times are a decision nobody wants
  /// to make for something that arrives all day.
  static const _step = 30;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xl),
      child: Column(
        children: [
          const Spacer(),
          const FluidOrb(size: 120, glow: false),
          const Spacer(),
          Text(
            'Set daily Motivation reminders',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.text,
            ),
          ),
          const SizedBox(height: AppSpacing.xxl),
          _Stepper(
            label: 'How many',
            value: '$count',
            // One a day is the floor, because zero is "turn it off" and that
            // belongs in settings, not hidden at the end of a stepper.
            onMinus: count > 1 ? () => onCount(count - 1) : null,
            onPlus: count < MotivationProvider.maxPerDay
                ? () => onCount(count + 1)
                : null,
          ),
          _Stepper(
            label: 'Start at',
            value: _clock(start),
            onMinus: start - _step >= 0 ? () => onStart(start - _step) : null,
            // Never past the end: a window that runs backwards schedules
            // nothing, and the failure would be silent.
            onPlus: start + _step < end ? () => onStart(start + _step) : null,
          ),
          _Stepper(
            label: 'End at',
            value: _clock(end),
            onMinus: end - _step > start ? () => onEnd(end - _step) : null,
            onPlus: end + _step <= 23 * 60 + 30 ? () => onEnd(end + _step) : null,
          ),
          const Spacer(flex: 2),
          _Cta(label: 'Continue', onTap: onContinue),
        ],
      ),
    );
  }

  static String _clock(int minutes) {
    final h24 = minutes ~/ 60;
    final m = minutes % 60;
    final period = h24 < 12 ? 'AM' : 'PM';
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h:${m.toString().padLeft(2, '0')} $period';
  }
}

/// A label with a minus, a value and a plus, as in the reference.
class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;

  /// Null disables the side, which is how a limit is shown: a button that does
  /// nothing when pressed is worse than one that looks unavailable.
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w600, color: c.text),
            ),
          ),
          _Round(icon: Icons.remove_rounded, onTap: onMinus),
          SizedBox(
            width: 96,
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: c.text),
            ),
          ),
          _Round(icon: Icons.add_rounded, onTap: onPlus),
        ],
      ),
    );
  }
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final on = onTap != null;
    return OmTappable(
      onTap: on
          ? () {
              Haptics.light();
              onTap!();
            }
          : null,
      feedback: OmTapFeedback.none,
      pressedScale: 0.92,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.border),
        ),
        child: Icon(icon,
            size: 20, color: on ? c.primary : c.text2.withValues(alpha: 0.4)),
      ),
    );
  }
}

/// Screen three: what the lines should be about.
class _Areas extends StatelessWidget {
  const _Areas({
    required this.picked,
    required this.onToggle,
    required this.onFinish,
  });

  final Set<MotivationCategory> picked;
  final ValueChanged<MotivationCategory> onToggle;
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
      child: Column(
        children: [
          const Spacer(),
          Text(
            'What areas of your life would\nyou like to improve?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 21,
              height: 1.3,
              fontWeight: FontWeight.w800,
              color: c.text,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          // Two columns, as in the reference. Wrap rather than a grid, so a
          // long label at a large text size takes the height it needs instead
          // of being clipped into a fixed cell.
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            alignment: WrapAlignment.center,
            children: [
              for (final cat in MotivationCategory.values)
                _AreaChip(
                  label: cat.label,
                  on: picked.contains(cat),
                  onTap: () => onToggle(cat),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            picked.isEmpty
                ? 'pick as many as you like, or none and we will vary it'
                : '${picked.length} chosen',
            style: TextStyle(fontSize: 12.5, color: c.text2),
          ),
          const Spacer(flex: 2),
          _Cta(label: 'Finish', onTap: onFinish),
        ],
      ),
    );
  }
}

class _AreaChip extends StatelessWidget {
  const _AreaChip({required this.label, required this.on, required this.onTap});

  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.96,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: (MediaQuery.sizeOf(context).width - AppSpacing.xl * 2 - AppSpacing.md) / 2,
        padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        decoration: BoxDecoration(
          // Peach for chosen rather than the brand purple: purple is what
          // commits on this flow, and a selected chip has not committed to
          // anything until Finish.
          color: on ? c.accentTint : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: on ? c.accent : c.border, width: on ? 1.5 : 1),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: on ? FontWeight.w800 : FontWeight.w600,
            color: on ? c.text : c.text2,
          ),
        ),
      ),
    );
  }
}

/// The full-width commit button that ends every page.
class _Cta extends StatelessWidget {
  const _Cta({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.98,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.primary,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: c.primary.withValues(alpha: 0.3),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
