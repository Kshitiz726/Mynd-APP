import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/api_client.dart';
import '../../core/services/api_config.dart';
import '../../core/services/coach_memory_service.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';

import '../../providers/nav_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_switch.dart';
import '../../widgets/om_tappable.dart';
import '../memory/memory_screen.dart';
import 'about_screen.dart';
import 'activity_history_screen.dart';

/// Settings.
///
/// Rebuilt on the reference: a portrait and a name at the top, a plan card, and
/// after that nothing but quiet grouped rows with chevrons.
///
/// The previous version had five sections, eighteen rows, and every icon in a
/// different colour, which turned a settings page into a fairground. Most of it
/// was not settings either: "write a review", "redeem a code", "auto low-stim
/// on brain-dead". Those are gone.
///
/// What stayed had to earn it. The sensory toggles are not decoration in an
/// ADHD app, they are the accessibility layer, so low-stim, dark mode,
/// hyperlegible type, haptics and reduced motion all remain. Memory and
/// activity history are here because this screen is their only entrance;
/// deleting the row would delete the feature. Notes went the other way: it was
/// a second, worse place to write things down next to the coach and the
/// backlog, so it is gone rather than kept out of politeness.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Confirm, then fully tear down the session: clear the saved token, drop the
  /// realtime socket, wipe this device's coach memory (so the next account on
  /// the same device starts clean), and return to the login screen.
  Future<void> _confirmSignOut(BuildContext context) async {
    Haptics.medium();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            "You'll need to continue with Google again to come back in."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('Sign out', style: TextStyle(color: ctx.omColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    await ApiClient.instance.signOut();
    RealtimeService.instance.dispose();
    await CoachMemoryService.instance.clearAll();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final c = context.omColors;
    final name = ApiConfig.instance.displayName ?? 'your account';
    final handle = ApiConfig.instance.handle;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 4,
              AppSpacing.screenH, AppSpacing.screenBottom),
          children: [
            // ── Header: back, title, nothing else ──
            Row(
              children: [
                _CircleButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.read<NavProvider>().select(AppTab.today);
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    'Settings',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 19),
                  ),
                ),
                // Balances the back button so the title sits truly centred.
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Who you are ──
            Center(
              child: Column(
                children: [
                  OmAvatar(
                    userId: ApiConfig.instance.userId ?? '',
                    fallbackInitial:
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                    fallbackColor: c.primary,
                    size: 92,
                  ),
                  const SizedBox(height: 14),
                  Text(name,
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontSize: 20)),
                  if (handle != null) ...[
                    const SizedBox(height: 3),
                    Text(handle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: c.text2)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── The plan ──
            _PlanCard(
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.paywall)),
            const SizedBox(height: AppSpacing.xl),

            const _GroupLabel('Account'),
            _Group(children: [
              _Row(
                icon: Icons.person_outline_rounded,
                label: 'Account',
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.paywall),
              ),
              _Row(
                icon: Icons.notifications_none_rounded,
                label: 'Reminders',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.reminders),
              ),
              _Row(
                icon: Icons.psychology_outlined,
                label: 'Memory',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MemoryScreen()),
                ),
              ),
              _Row(
                icon: Icons.history_rounded,
                label: 'Activity history',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const ActivityHistoryScreen()),
                ),
                last: true,
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),

            // ── The accessibility layer. Not decoration in an app for ADHD. ──
            const _GroupLabel('How it feels'),
            _Group(children: [
              _ToggleRow(
                icon: Icons.blur_on_rounded,
                label: 'Low stimulation',
                value: settings.lowStim,
                onChanged: (_) => settings.toggleLowStim(),
              ),
              _ToggleRow(
                icon: Icons.dark_mode_outlined,
                label: 'Dark mode',
                value: settings.darkMode,
                onChanged: (_) => settings.toggleDarkMode(),
              ),
              _ToggleRow(
                icon: Icons.text_fields_rounded,
                label: 'Hyperlegible font',
                value: settings.hyperlegible,
                onChanged: (_) => settings.toggleHyperlegible(),
              ),
              _ToggleRow(
                icon: Icons.vibration_rounded,
                label: 'Haptics',
                value: settings.haptics,
                onChanged: (_) => settings.toggleHaptics(),
              ),
              _ToggleRow(
                icon: Icons.motion_photos_off_outlined,
                label: 'Reduce motion',
                value: settings.reduceMotion,
                onChanged: (_) => settings.toggleReduceMotion(),
                last: true,
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),

            const _GroupLabel('Settings'),
            _Group(children: [
              _Row(
                icon: Icons.help_outline_rounded,
                label: 'Help & Support',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                ),
              ),
              _Row(
                icon: Icons.logout_rounded,
                label: 'Logout',
                danger: true,
                onTap: () => _confirmSignOut(context),
                last: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The plain circular control in the header corner.
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.88,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
        child: Icon(icon, size: 24, color: c.text),
      ),
    );
  }
}

/// The gradient plan banner from the reference.
class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.onTap});

  final VoidCallback onTap;

  /// Nobody has paid yet, because there is nothing to pay with yet. Until
  /// billing exists this is false, and the card tells the truth: you are on the
  /// free plan. Calling everyone Premium while charging nobody trains people to
  /// ignore the one label that will eventually mean something.
  static const bool _isPremium = false;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: () {
        Haptics.medium();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: _isPremium ? c.brandGradient : null,
          color: _isPremium ? null : c.surface,
          borderRadius: BorderRadius.circular(18),
          border: _isPremium ? null : Border.all(color: c.border),
          boxShadow: _isPremium
              ? [
                  BoxShadow(
                    color: c.primary.withValues(alpha: 0.34),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _isPremium
                    ? Colors.white.withValues(alpha: 0.22)
                    : c.primaryTint,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _isPremium
                    ? Icons.workspace_premium_rounded
                    : Icons.auto_awesome_outlined,
                color: _isPremium ? Colors.white : c.primary,
                size: 21,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isPremium ? 'Premium Account' : 'Free plan',
                    style: TextStyle(
                        color: _isPremium ? Colors.white : c.text,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _isPremium
                        ? 'Enjoy your premium features'
                        : 'See what Premium adds',
                    style: TextStyle(
                      color: _isPremium
                          ? Colors.white.withValues(alpha: 0.82)
                          : c.text2,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            if (!_isPremium)
              Icon(Icons.chevron_right_rounded, color: c.text2, size: 20),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.omColors.text2,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// A rounded card holding a run of rows, hairline-separated.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border.withValues(alpha: 0.6)),
      ),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.last = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool last;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tint = danger ? c.error : c.text;
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(
                  bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
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
            Icon(Icons.chevron_right_rounded, size: 20, color: c.text2),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
    this.last = false,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: c.text),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
          ),
          OmSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
