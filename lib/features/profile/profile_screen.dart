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
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../providers/nav_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/om_button.dart';
import '../../widgets/om_card.dart';
import '../../widgets/om_states.dart';
import '../../widgets/om_switch.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_top_bar.dart';
import '../../widgets/om_tappable.dart';
import 'about_screen.dart';
import 'activity_history_screen.dart';

/// "you" — profile, vault links, and the sensory/accessibility toggles that
/// drive the app's global behavior. The toggles are wired straight to
/// [SettingsProvider], so flipping them changes the whole app live.
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
        content: const Text("You'll need to continue with Google again to come back in."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Sign out', style: TextStyle(color: ctx.omColors.error)),
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

    // Always sits inside its own Scaffold so it has a proper background whether
    // shown as the "you" tab or pushed as a standalone route (previously the
    // route had no surface and rendered black).
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenH, AppSpacing.screenTop, AppSpacing.screenH, AppSpacing.screenBottom),
          children: [
            OmTopBar(
              title: 'you',
              subtitle: handle == null ? name : '$name · $handle',
              leading: const OmBackButton(),
              actions: [
                OmTopBarAction(
                  icon: OmIcons.byName('close'),
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.read<NavProvider>().select(AppTab.today);
                    }
                  },
                ),
              ],
            ),

            // Current Plan Card (Replaces Sharing is caring)
            OmTappable(
              onTap: () => Navigator.of(context).pushNamed(AppRoutes.paywall),
              child: Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFF161616),
                  gradient: const RadialGradient(
                    center: Alignment(0.5, -0.5),
                    radius: 1.5,
                    colors: [
                      Color(0xFF3B1E4A), // Subtle purple/pink glow
                      Color(0xFF161616),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Free Plan', style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 32)),
                        const SizedBox(height: 24),
                        Text('Complimentary', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.85), fontWeight: FontWeight.w600, fontSize: 16)),
                        const SizedBox(height: 4),
                        Text('Just the basics', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.6), fontSize: 14)),
                      ],
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check, size: 14, color: Colors.black),
                            const SizedBox(width: 4),
                            const Text('Active', style: TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.w700)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            _SettingsGroup(
              title: 'account',
              children: [
                _SettingsItem(
                  icon: 'user', iconColor: c.primary, label: 'Manage account',
                  onTap: () {},
                ),
                _SettingsItem(
                  icon: 'credit-card', iconColor: const Color(0xFF10B981), label: 'Manage subscription',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.paywall),
                ),
                _SettingsItem(
                  icon: 'gift', iconColor: const Color(0xFFF59E0B), label: 'Redeem a code',
                  onTap: () {},
                ),
                _SettingsItem(
                  icon: 'bell', iconColor: const Color(0xFFEC4899), label: 'Notifications',
                  onTap: () {},
                ),
                _SettingsItem(
                  icon: 'bell', iconColor: const Color(0xFF3B82F6), label: 'Reminders', trailing: '2 active',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.reminders),
                ),
              ],
            ),

            _SettingsGroup(
              title: 'my vault',
              children: [
                _SettingsItem(
                  icon: 'clock', iconColor: const Color(0xFF8B5CF6), label: 'Activity history',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ActivityHistoryScreen())),
                ),
                _SettingsItem(
                  icon: 'edit', iconColor: const Color(0xFFF43F5E), label: 'Notebook & files', trailing: '12 notes',
                  onTap: () => Navigator.of(context).pushNamed(AppRoutes.notes),
                ),
              ],
            ),

            _SettingsGroup(
              title: 'sensory & accessibility',
              children: [
                _SettingsToggle(
                  icon: 'eye', iconColor: const Color(0xFF6366F1), label: 'Low stimulation mode',
                  value: settings.lowStim, onChanged: settings.toggleLowStim,
                ),
                _SettingsToggle(
                  icon: 'zap', iconColor: const Color(0xFFF59E0B), label: 'Auto low-stim on brain-dead',
                  value: settings.autoLowStim, onChanged: settings.toggleAutoLowStim,
                ),
                _SettingsToggle(
                  icon: 'moon', iconColor: const Color(0xFF1E293B), label: 'Dark mode',
                  value: settings.darkMode, onChanged: settings.toggleDarkMode,
                ),
                _SettingsToggle(
                  icon: 'type', iconColor: const Color(0xFF14B8A6), label: 'Hyperlegible font',
                  value: settings.hyperlegible, onChanged: settings.toggleHyperlegible,
                ),
                _SettingsToggle(
                  icon: 'smartphone', iconColor: const Color(0xFF8B5CF6), label: 'Haptics',
                  value: settings.haptics, onChanged: settings.toggleHaptics,
                ),
                _SettingsToggle(
                  icon: 'wind', iconColor: const Color(0xFF06B6D4), label: 'Reduce animation',
                  value: settings.reduceMotion, onChanged: settings.toggleReduceMotion,
                ),
              ],
            ),

            _SettingsGroup(
              title: 'support',
              children: [
                _SettingsItem(
                  icon: 'mail', iconColor: c.text2, label: 'Contact us',
                  onTap: () {},
                ),
                _SettingsItem(
                  icon: 'star', iconColor: const Color(0xFFF59E0B), label: 'Write a review',
                  onTap: () {},
                ),
                _SettingsItem(
                  icon: 'info', iconColor: c.text2, label: 'About OurMynd',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutScreen())),
                ),
              ],
            ),

            _SettingsGroup(
              children: [
                _SettingsItem(
                  icon: 'logout', iconColor: c.error, label: 'Sign out',
                  labelColor: c.error,
                  hideChevron: true,
                  onTap: () => _confirmSignOut(context),
                ),
              ],
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({this.title, required this.children});
  final String? title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null) ...[
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8, top: 16),
            child: Text(title!.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
          ),
        ],
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border.withValues(alpha: 0.5)),
          ),
          child: Column(
            children: [
              for (int i = 0; i < children.length; i++) ...[
                children[i],
                if (i < children.length - 1)
                  Padding(
                    padding: const EdgeInsets.only(left: 56),
                    child: Divider(height: 1, thickness: 1, color: c.border.withValues(alpha: 0.5)),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _SettingsItem extends StatelessWidget {
  const _SettingsItem({required this.icon, required this.iconColor, required this.label, this.trailing, this.labelColor, this.hideChevron = false, required this.onTap});

  final String icon;
  final Color iconColor;
  final String label;
  final String? trailing;
  final Color? labelColor;
  final bool hideChevron;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(8)),
              child: Icon(OmIcons.byName(icon), size: 16, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: labelColor ?? c.text, fontWeight: FontWeight.w500))),
            if (trailing != null) ...[
              Text(trailing!, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
              const SizedBox(width: 8),
            ],
            if (!hideChevron)
              Icon(OmIcons.byName('chevR'), size: 16, color: c.text2.withValues(alpha: 0.5)),
          ],
        ),
      ),
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  const _SettingsToggle({required this.icon, required this.iconColor, required this.label, required this.value, required this.onChanged});

  final String icon;
  final Color iconColor;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(color: iconColor, borderRadius: BorderRadius.circular(8)),
            child: Icon(OmIcons.byName(icon), size: 16, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(child: Text(label, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.text, fontWeight: FontWeight.w500))),
          OmSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
