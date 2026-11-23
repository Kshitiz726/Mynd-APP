import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/legal.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/services/ai/ai_connections.dart';
import '../../core/services/ai/ai_router.dart';
import '../../providers/ai_consent_provider.dart';
import '../../widgets/om_tappable.dart';

/// The one thing to agree to before the coach can be used: that what you type
/// is sent to a third-party AI provider to generate the reply.
///
/// Apple's Guideline 5.1.2(i) is the shape of this screen. It requires that,
/// before personal data goes to a third-party AI service, the app says what is
/// sent, names who it goes to, and gets permission. So this screen:
///
/// * **Names the provider.** The company is on the screen, not hidden behind "our
///   AI". Who the data goes to is the whole point of the disclosure.
/// * **Says what leaves.** What you type, and the context the coach is given -
///   not a vague "some data".
/// * **Is asked before the first turn, and the send is what it gates.** Agree
///   and the coach opens; decline and the coach is simply unavailable, because
///   the provider is where the reply comes from and there is no coach without
///   it. The rest of the app is untouched either way.
///
/// Unlike the health-data question, declining here is not a "colder coach" - it
/// is "no coach". That is not a punishment, it is the honest consequence: this
/// feature cannot run without sending your words off the account, so the only
/// way to not send them is to not use it. It is shown again if the disclosure
/// changes materially; the server reports agreement to superseded wording as
/// undecided. See server/src/routes/consent.ts.
class AiConsentScreen extends StatefulWidget {
  const AiConsentScreen({
    super.key,
    required this.onDecided,
    this.source = 'coach',
  });

  /// Called once an answer is recorded, either way. The caller decides where to
  /// go next: this is used both as the coach gate and from Settings.
  final ValueChanged<bool> onDecided;

  /// Where the question was asked: 'coach', 'settings' or 'connect'. Goes into
  /// the consent record, which is an audit trail and should say which screen
  /// the person was actually looking at when they answered.
  final String source;

  @override
  State<AiConsentScreen> createState() => _AiConsentScreenState();
}

class _AiConsentScreenState extends State<AiConsentScreen> {
  bool _saving = false;

  Future<void> _answer(bool granted) async {
    if (_saving) return;
    setState(() => _saving = true);
    granted ? Haptics.success() : Haptics.light();

    // Records the answer on this device and syncs it after. It does not throw:
    // an unreachable server must not be able to stop somebody answering a
    // consent question, which is what used to happen here. The gate reads the
    // recorded answer, so a deferred sync cannot send anything early.
    // The company named on this very screen is the one recorded, so the record
    // says what was actually agreed to rather than what is active later.
    final company = AiRouter.instance.activeCompany;
    final consent = AiConsentProvider.instance;
    if (granted) {
      await consent.grant(source: widget.source, company: company);
    } else {
      await consent.withdraw(source: widget.source, company: company);
    }

    if (mounted) widget.onDecided(granted);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    // Named, not hardcoded. Naming the recipient is the thing 5.1.2(i) asks
    // for, so the moment somebody connects their own Claude or Gemini account
    // a screen still saying "Groq" stops being true. Watched, so switching
    // provider in Settings rewrites this screen rather than leaving it stale.
    //
    // Reads the *effective* provider: a chosen provider that is not connected
    // falls back to the built-in one, and naming a provider the fallback
    // quietly bypassed would be worse than naming none at all.
    context.watch<AiConnections>();
    final company = AiRouter.instance.activeCompany;

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
                      child: Icon(LucideIcons.sparkles, color: c.primary, size: 26),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    Text('how the coach works', style: t.headlineSmall),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'The coach does not run on this phone. Its replies are '
                      'written by a third-party AI provider, $company, so to '
                      'answer you, what you type has to be sent to them. We want '
                      'to be straight about that before you start, not bury it '
                      'in the terms.',
                      style: t.bodyMedium?.copyWith(color: c.text2, height: 1.55),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    _WhatFor(
                      icon: LucideIcons.messageCircle,
                      title: 'what you type',
                      body: 'The messages you send the coach are forwarded to '
                          '$company to generate each reply.',
                    ),
                    const _WhatFor(
                      icon: LucideIcons.send,
                      title: 'the context it is given',
                      body: 'Along with your message, the coach is given the '
                          'context it needs to reply. If you have allowed us to '
                          'use your health data, that context includes your mood '
                          'and memory; if not, it does not.',
                    ),
                    const _WhatFor(
                      icon: LucideIcons.shieldCheck,
                      title: 'only to reply to you',
                      body: 'It is sent over an encrypted connection, used to '
                          'produce the coach\'s answer, and nothing else. The '
                          'privacy policy sets out the detail.',
                      last: true,
                    ),

                    const SizedBox(height: AppSpacing.lg),
                    _Reassurance(
                      lines: [
                        'Agreeing is only for the coach. Everything else in the '
                            'app works whether you do or not.',
                        'You can change your mind in Settings at any time; the '
                            'coach then stops.',
                        'Decline and nothing of yours is sent to $company.',
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

            // Two answers, weighted the same. Neither is pre-selected and there
            // is no way off this screen that is not one of them being pressed.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH, AppSpacing.sm, AppSpacing.screenH, AppSpacing.lg),
              child: Column(
                children: [
                  _Answer(
                    label: 'agree, open the coach',
                    filled: true,
                    enabled: !_saving,
                    onTap: () => _answer(true),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _Answer(
                    label: 'not now',
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

/// One "here is what happens" row: icon, a plain heading, and the actual thing.
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

/// The promises made about this agreement, said where the decision is made
/// rather than only in the document.
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

/// One of the two answers. Same size and shape; only the fill differs, so the
/// screen has a visual centre, not so one answer is easier to give.
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
