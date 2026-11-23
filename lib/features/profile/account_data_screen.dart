import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/config/store_policy.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/account_scope.dart';
import '../../core/services/api_client.dart';
import '../../core/services/api_config.dart';
import '../../core/services/coach_memory_service.dart';
import '../../core/services/google_auth.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';

/// Settings → Your data. Export and deletion.
///
/// Both endpoints existed on the server with no way to reach them from the app,
/// which is the same as not having them: UK GDPR Art. 17 and 20 are rights the
/// user exercises, and App Store Guideline 5.1.1(v) requires the deletion route
/// to be *in the app*, not in a support inbox.
class AccountDataScreen extends StatefulWidget {
  const AccountDataScreen({super.key});

  @override
  State<AccountDataScreen> createState() => _AccountDataScreenState();
}

class _AccountDataScreenState extends State<AccountDataScreen> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    Haptics.light();
    try {
      final data = await ApiClient.instance.exportMyData();
      final pretty = const JsonEncoder.withIndent('  ').convert(data);
      if (!mounted) return;
      setState(() => _busy = false);

      // Copied to the clipboard rather than written to a file.
      //
      // A file needs a share sheet and a platform path, and the thing people
      // actually do with an export is paste it somewhere. The full document is
      // also shown on screen, so this is legible as well as portable, and it
      // works identically on both platforms with no new dependency.
      await Clipboard.setData(ClipboardData(text: pretty));
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Copied'),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: SingleChildScrollView(
              child: SelectableText(
                pretty,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 10.5),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Done'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      Toast.show(context, "Couldn't build your export. Try again in a moment.");
    }
  }

  Future<void> _delete() async {
    final expected = ApiConfig.instance.displayName ?? '';
    final controller = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This removes your account and everything in it: tasks, goals, '
              'notes, messages you sent, your mood history and the memory the '
              'coach kept. It cannot be undone.\n',
            ),
            Text('Type $expected to confirm.'),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Delete', style: TextStyle(color: ctx.omColors.error)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      // The server checks the confirmation too, so a client that skipped this
      // dialog would still be refused.
      // Captured before the call: deleteAccount signs out, which clears the id
      // the purge needs to find this account's parked keys.
      final userId = ApiConfig.instance.userId;

      await ApiClient.instance.deleteAccount(confirm: controller.text.trim());

      // Everything local goes with it. Clearing coach memory alone left the
      // schedule, goals, mood history, feed and the Gmail credential sitting
      // on the device - so an account that had just been erased came back the
      // moment anybody signed in, which is not what "delete my account" says.
      await GoogleAuth.forget();
      RealtimeService.instance.dispose();
      await CoachMemoryService.instance.clearAll();
      if (userId != null) await AccountScope.purge(userId);

      if (!mounted) return;
      // A full rebuild, not a navigation.
      //
      // Clearing the keys is only half of it. Every provider built at launch is
      // still holding this account's tasks, goals, mood history and chat in
      // memory, and the next thing any of them persists writes it all straight
      // back over the keys that were just cleared - which is exactly what
      // happened: the name went, and the conversation came back. Navigating to
      // login leaves that tree standing. This is the same restart a switch
      // does, pointed at login instead of the shell.
      final restart = AccountScope.onSwitched;
      if (restart != null) {
        restart(AppRoutes.login);
      } else {
        Navigator.of(context, rootNavigator: true)
            .pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Only a 400 is the name not matching. Every other failure said the same
      // thing, which blamed the user's typing for a fault on the server - and
      // in the one case that actually happened (a foreign key that stopped the
      // account row being deleted) it sent people round the same loop, typing
      // their name more carefully, while the account survived every attempt.
      Toast.show(
        context,
        e.statusCode == 400
            ? "That didn't match. Nothing was deleted."
            : 'Your account could not be deleted just now, and nothing was '
                'changed. Please try again, or contact support if it keeps '
                'happening.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      debugPrint('[account] delete failed: $e');
      Toast.show(
        context,
        'Your account could not be deleted just now, and nothing was changed.',
      );
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, AppSpacing.screenH, 8),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 6),
                  Text('Your data', style: t.titleLarge),
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
                    Text('take a copy',
                        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Everything stored about your account, as one JSON file: '
                      'your profile, tasks, goals, notes, posts, the messages '
                      'you sent, your mood history and your consent record.\n\n'
                      'Messages other people sent you are not included, because '
                      'they are their information as well as yours.',
                      style: t.bodyMedium?.copyWith(color: c.text2, height: 1.55),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _Action(
                      label: 'export my data',
                      icon: LucideIcons.download,
                      danger: false,
                      enabled: !_busy,
                      onTap: _export,
                    ),

                    const SizedBox(height: AppSpacing.xxl),
                    Text('delete everything',
                        style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      // The billing sentence only where the build can sell.
                      // It named Stripe, on a screen that is not gated, so an
                      // iOS user who can not buy anything was being warned
                      // about a processor this app never puts in front of them
                      // - and the privacy policy now says, truthfully, that no
                      // payment is taken. Naming no provider keeps it correct
                      // on the builds that do sell, whoever processes it.
                      'Your account and all of its contents are removed. This '
                      'is immediate and cannot be undone. Signing in again '
                      'afterwards creates a brand new, empty account.'
                      '${StorePolicy.canSell ? '\n\nIf you have a '
                          'subscription, cancel it first: deleting the '
                          'account does not stop billing on its own.' : ''}',
                      style: t.bodyMedium?.copyWith(color: c.text2, height: 1.55),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _Action(
                      label: 'delete my account',
                      icon: LucideIcons.trash2,
                      danger: true,
                      enabled: !_busy,
                      onTap: _delete,
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

/// A full-width action row, matching the health-data screen's.
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
        onTap: enabled ? onTap : null,
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
