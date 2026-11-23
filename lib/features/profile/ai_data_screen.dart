import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/legal.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../core/services/ai/ai_connections.dart';
import '../../core/services/ai/ai_router.dart';
import '../../providers/ai_consent_provider.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';

/// Settings -> Coach & AI. Where the agreement to send coach messages to the
/// third-party AI provider can be read back and taken away.
///
/// The disclosure screen promises the decision "can be changed in Settings at
/// any time", so this screen has to exist and has to make the change a single
/// obvious action. Withdrawing here turns the coach off (the provider is where
/// its replies come from) and touches nothing else. There is no "delete stored
/// data" action because this consent governs transmission, not storage: what
/// was sent to generate a reply is not kept by us, and the mood and memory that
/// may have gone with it are the health screen's to erase.
class AiDataScreen extends StatefulWidget {
  const AiDataScreen({super.key});

  @override
  State<AiDataScreen> createState() => _AiDataScreenState();
}

class _AiDataScreenState extends State<AiDataScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The server is the record. Reconcile on open, in case it was changed on
    // another device.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AiConsentProvider.instance.refresh();
    });
  }

  Future<void> _withdraw() async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Turn off the coach?'),
        content: const Text(
          'Your messages will no longer be sent to the AI provider, which means '
          'the coach can no longer reply and will be unavailable. Everything '
          'else in the app carries on exactly as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Turn off'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await AiConsentProvider.instance.withdraw(source: 'settings');
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, "Couldn't save that. Check your connection and try again.");
    }
  }

  Future<void> _grant() async {
    setState(() => _busy = true);
    Haptics.success();
    try {
      await AiConsentProvider.instance.grant(source: 'settings');
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, "Couldn't save that. Check your connection and try again.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    final consent = context.watch<AiConsentProvider>();
    final granted = consent.granted;
    // Named dynamically: this screen is where somebody checks who their
    // words go to, so it must say whoever that currently is.
    context.watch<AiConnections>();
    final company = AiRouter.instance.activeCompany;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, AppSpacing.screenH, 8),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 6),
                  Text('Coach & AI', style: t.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
                    AppSpacing.md, AppSpacing.screenH, AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StateCard(
                      granted: granted,
                      decidedAt: consent.decidedAt,
                      awaitingSync: consent.awaitingSync,
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    Text('what this covers', style: t.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'The coach\'s replies are generated by a third-party AI '
                      'provider, $company. To answer you, the messages you '
                      'send the coach, and the context it is given, are sent to '
                      'them. Agreeing here is what allows that; without it the '
                      'coach cannot reply and is turned off.',
                      style: t.bodyMedium?.copyWith(color: c.text2, height: 1.55),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'This is separate from the health-data question. Your '
                      'mood and memory are only ever part of what is sent if you '
                      'have also allowed that, on the Health data screen.',
                      style: t.bodySmall?.copyWith(color: c.text2, height: 1.5),
                    ),

                    const SizedBox(height: AppSpacing.xl),
                    if (granted)
                      _Action(
                        label: 'turn off the coach',
                        icon: LucideIcons.shieldOff,
                        danger: true,
                        enabled: !_busy,
                        onTap: _withdraw,
                      )
                    else
                      _Action(
                        label: 'turn on the coach',
                        icon: LucideIcons.shieldCheck,
                        danger: false,
                        enabled: !_busy,
                        onTap: _grant,
                      ),

                    const SizedBox(height: AppSpacing.xl),
                    OmTappable(
                      onTap: () => Legal.openPrivacy(context),
                      feedback: OmTapFeedback.light,
                      pressedScale: 0.98,
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
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The current answer and when it was given. A consent record the person
/// cannot read back is not much of a record.
class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.granted,
    required this.decidedAt,
    required this.awaitingSync,
  });

  final bool granted;
  final DateTime? decidedAt;

  /// The answer is saved here but has not reached the server yet. Said out
  /// loud, because "saved on this device" and "saved on your account" are
  /// different promises and this screen is the record of which one was made.
  final bool awaitingSync;

  static const _months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    final tint = granted ? c.success : c.text2;
    final at = decidedAt;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(granted ? LucideIcons.shieldCheck : LucideIcons.shieldOff,
                size: 20, color: tint),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(granted ? 'Coach is on' : 'Coach is off',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  at == null
                      ? (granted ? 'Agreed on this account.' : 'Not currently agreed.')
                      : granted
                          ? 'Agreed on ${_date(at)}.'
                          : 'Declined or turned off on ${_date(at)}.',
                  style: t.bodySmall?.copyWith(color: c.text2, height: 1.45),
                ),
                if (awaitingSync) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Saved on this device. It will reach your account the next '
                    'time the app can talk to the server.',
                    style: t.bodySmall?.copyWith(
                      color: c.attention,
                      height: 1.45,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width action row, standing alone because it is a decision, not a
/// setting.
class _Action extends StatelessWidget {
  const _Action({
    required this.label,
    required this.icon,
    required this.danger,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool danger;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tint = danger ? c.error : c.primary;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: OmTappable(
        onTap: enabled
            ? () {
                Haptics.light();
                onTap();
              }
            : null,
        enabled: enabled,
        feedback: OmTapFeedback.none,
        pressedScale: 0.99,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: c.border.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: tint),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(color: tint)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
