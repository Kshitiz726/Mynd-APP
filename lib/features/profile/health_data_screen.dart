import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/legal.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../providers/health_consent_provider.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';

/// Settings → Health data. Where the consent given during onboarding can be
/// read back and taken away again.
///
/// The policy promises consent "can be withdrawn in Settings at any time
/// without losing access to the rest of the app", and that is three separate
/// obligations this screen has to meet: it has to *show* the current state
/// (including when it was decided, so the record is theirs too, not only ours),
/// it has to make withdrawal a single obvious action rather than something to
/// go hunting for, and it has to leave afterwards without having taken anything
/// else away.
///
/// The deletion offer is deliberately a second, separate step after
/// withdrawing. Stopping and erasing are different things to want, and rolling
/// them into one button would mean anyone who wanted the first silently got the
/// second - losing a mood history they may have been keeping for a doctor.
class HealthDataScreen extends StatefulWidget {
  const HealthDataScreen({super.key});

  @override
  State<HealthDataScreen> createState() => _HealthDataScreenState();
}

class _HealthDataScreenState extends State<HealthDataScreen> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // The server is the record. Opening this screen is the moment to reconcile
    // with it, in case the answer was changed on another device.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HealthConsentProvider.instance.refresh();
    });
  }

  Future<void> _withdraw() async {
    final consent = HealthConsentProvider.instance;
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Withdraw consent?'),
        content: const Text(
          'The coach will stop being given your mood, your energy and what you '
          'have talked about before, and will stop building a memory from them. '
          'Everything else in the app carries on exactly as it is.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await consent.withdraw(source: 'settings');
      if (!mounted) return;
      setState(() => _busy = false);
      // Only now, once it has actually stopped, is deleting the past a
      // separate question worth asking.
      await _offerDeletion();
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
      await HealthConsentProvider.instance.grant(source: 'settings');
      if (mounted) setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, "Couldn't save that. Check your connection and try again.");
    }
  }

  Future<void> _offerDeletion() async {
    final wants = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete what was stored?'),
        content: const Text(
          'Your mood history and the memory the coach had written about you can '
          'be deleted now. Your tasks, goals, habits and notes are not touched.\n\n'
          'You can also keep them - consent is withdrawn either way.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep them'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (wants != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await HealthConsentProvider.instance.deleteStoredData();
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, 'Deleted.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, "Couldn't delete that right now. Try again in a moment.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    final consent = context.watch<HealthConsentProvider>();
    final granted = consent.granted;

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
                  Text('Health data', style: t.titleLarge),
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
                    _StateCard(granted: granted, decidedAt: consent.decidedAt),
                    const SizedBox(height: AppSpacing.xl),

                    Text('what this covers', style: t.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Your mood check-ins, your energy levels, the thoughts you '
                      'park, and what you and the coach talk about. With consent '
                      'these are given to the coach and used to keep a written '
                      'memory of what matters to you. Without it, none of them '
                      'reach the coach and no memory is written.',
                      style: t.bodyMedium?.copyWith(color: c.text2, height: 1.55),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Your tasks, goals, habits, focus sessions and notes are '
                      'not covered by this and are never affected by it.',
                      style: t.bodySmall?.copyWith(color: c.text2, height: 1.5),
                    ),

                    const SizedBox(height: AppSpacing.xl),
                    if (granted)
                      _Action(
                        label: 'withdraw consent',
                        icon: LucideIcons.shieldOff,
                        danger: true,
                        enabled: !_busy,
                        onTap: _withdraw,
                      )
                    else
                      _Action(
                        label: 'give consent',
                        icon: LucideIcons.shieldCheck,
                        danger: false,
                        enabled: !_busy,
                        onTap: _grant,
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    // Reachable whatever the current answer is. Someone who
                    // declined at onboarding may still have data from before
                    // this screen existed, and someone who kept their history
                    // when withdrawing is allowed to change their mind later.
                    _Action(
                      label: 'delete stored health data',
                      icon: LucideIcons.trash2,
                      danger: true,
                      enabled: !_busy,
                      onTap: _offerDeletion,
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

/// The current answer and when it was given, stated plainly. A consent record
/// the person cannot read back is not much of a record.
class _StateCard extends StatelessWidget {
  const _StateCard({required this.granted, required this.decidedAt});

  final bool granted;
  final DateTime? decidedAt;

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
                Text(granted ? 'Consent given' : 'Consent not given',
                    style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  at == null
                      // Only reachable for an account whose answer predates the
                      // record, or one whose cache has not been reconciled yet.
                      ? (granted ? 'Given on this account.' : 'Not currently given.')
                      : granted
                          ? 'Given on ${_date(at)}.'
                          : 'Declined or withdrawn on ${_date(at)}.',
                  style: t.bodySmall?.copyWith(color: c.text2, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A full-width action row. Same shape as the settings groups elsewhere, but
/// standing alone because each of these is a decision, not a setting.
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
