import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/legal.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../providers/health_consent_provider.dart';
import '../../widgets/om_tappable.dart';

/// The health-data consent question, on a screen of its own.
///
/// Everything about the shape of this screen is the privacy policy's wording
/// rather than a design preference:
///
/// * **Its own screen.** The policy says this is not bundled into accepting the
///   Terms, so it cannot be a line in the sign-up flow's small print. It is a
///   separate question, asked once, on a page that asks nothing else.
/// * **Two real buttons, no pre-ticked box.** Consent has to be a deliberate
///   act. There is no default here to fall through: neither answer is
///   pre-selected, neither is styled as the one you are supposed to pick, and
///   the screen cannot be dismissed by swiping past it into a "yes".
/// * **Declining is a supported path, not a dead end.** "Not right now" is a
///   full-width button next to the other one, and it lands you in the app.
///   Whatever is built here must never make the decline branch feel like a
///   failure state, because the policy promises it costs nothing.
///
/// It is also shown again, later, if the health-data section of the policy
/// changes materially - the server reports consent given against superseded
/// wording as undecided. See server/src/routes/consent.ts.
class HealthConsentScreen extends StatefulWidget {
  const HealthConsentScreen({super.key, required this.onDecided});

  /// Called once an answer has been recorded, either way. The caller decides
  /// where to go next - this screen is used both as an onboarding step and
  /// from Settings, and it should not know which.
  final ValueChanged<bool> onDecided;

  @override
  State<HealthConsentScreen> createState() => _HealthConsentScreenState();
}

class _HealthConsentScreenState extends State<HealthConsentScreen> {
  bool _saving = false;

  Future<void> _answer(bool granted) async {
    if (_saving) return;
    setState(() => _saving = true);
    granted ? Haptics.success() : Haptics.light();

    final consent = HealthConsentProvider.instance;
    try {
      if (granted) {
        await consent.grant(source: 'onboarding');
      } else {
        await consent.withdraw(source: 'onboarding');
      }
      if (mounted) widget.onDecided(granted);
    } catch (e) {
      // The decision has to reach the server to count, so a failure here must
      // not look like it worked. Staying on the screen with the buttons live
      // is the honest outcome: nothing was recorded, and they can try again.
      if (mounted) {
        setState(() => _saving = false);
        Toast.show(context, "Couldn't save that. Check your connection and try again.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH, AppSpacing.xxl, AppSpacing.screenH, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Icon(LucideIcons.heartPulse, color: c.primary, size: 26),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text('one thing to ask you', style: t.headlineSmall),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'Some of what this app holds is health information: how '
                      'your energy and mood are going, what you park here at '
                      '2am, what you and the coach end up talking about. The '
                      'law treats that as a special category, and so do we, so '
                      'we ask about it on its own rather than folding it into '
                      'the terms you already accepted.',
                      style: t.bodyMedium?.copyWith(color: c.text2, height: 1.55),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    const _WhatFor(
                      icon: LucideIcons.messageCircle,
                      title: 'so the coach knows you',
                      body: 'Your energy, your mood check-ins and what you have '
                          'said before are given to the coach, so it can pick up '
                          'where you left off instead of meeting you cold.',
                    ),
                    const _WhatFor(
                      icon: LucideIcons.brain,
                      title: 'so it keeps a memory',
                      body: 'A short written picture of what matters to you, '
                          'built from those conversations. You can read it, edit '
                          'it and delete it whenever you like.',
                    ),
                    const _WhatFor(
                      icon: LucideIcons.trendingUp,
                      title: 'so patterns can surface',
                      body: 'Noticing that the hard days cluster, or that a week '
                          'has been heavier than usual, needs the history to '
                          'look back over.',
                      last: true,
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    const _Reassurance(
                      lines: [
                        'You can say no and keep using everything else.',
                        'You can change your mind in Settings at any time.',
                        'Withdrawing stops it, and you can delete what was kept.',
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    OmTappable(
                      onTap: () => Legal.openPrivacy(context),
                      feedback: OmTapFeedback.light,
                      pressedScale: 0.98,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('read the privacy policy',
                                style: t.labelLarge?.copyWith(
                                    color: c.primary, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 4),
                            Icon(LucideIcons.arrowUpRight, size: 16, color: c.primary),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // The two answers, weighted the same. Neither is pre-selected and
            // neither is a dismissal: there is no way off this screen that is
            // not one of them being pressed.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH, AppSpacing.sm, AppSpacing.screenH, AppSpacing.lg),
              child: Column(
                children: [
                  _Answer(
                    label: 'yes, use it to help me',
                    filled: true,
                    enabled: !_saving,
                    onTap: () => _answer(true),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Answer(
                    label: 'not right now',
                    filled: false,
                    enabled: !_saving,
                    onTap: () => _answer(false),
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

/// One "here is what it is for" row. Icon, a plain-language heading, and the
/// actual thing that happens - not a category name.
class _WhatFor extends StatelessWidget {
  const _WhatFor({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: c.text2),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(body,
                    style: t.bodySmall?.copyWith(color: c.text2, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The three promises the policy makes about this consent, said plainly and
/// where the decision is being made rather than only in the document.
class _Reassurance extends StatelessWidget {
  const _Reassurance({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: c.surfaceAlt,
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Padding(
              padding: EdgeInsets.only(bottom: line == lines.last ? 0 : AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(LucideIcons.check, size: 15, color: c.success),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(line,
                        style: t.bodySmall?.copyWith(color: c.text2, height: 1.45)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// One of the two answers. Same size, same shape, same touch target - only the
/// fill differs, and that is so the screen has a visual centre, not so one
/// answer is easier to give than the other.
class _Answer extends StatelessWidget {
  const _Answer({
    required this.label,
    required this.filled,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: OmTappable(
        onTap: enabled ? onTap : null,
        enabled: enabled,
        feedback: OmTapFeedback.none,
        pressedScale: 0.97,
        child: Container(
          height: 54,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: filled ? c.brandGradient : null,
            color: filled ? null : c.surface,
            border: filled ? null : Border.all(color: c.border, width: 1),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: filled ? Colors.white : c.text,
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
