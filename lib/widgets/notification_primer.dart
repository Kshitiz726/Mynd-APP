import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_spacing.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import '../core/utils/om_icons.dart';
import '../providers/reminders_provider.dart';
import '../services/notification_service.dart';
import 'om_tappable.dart';

/// Asks for notifications once, on the first run, and says why first.
///
/// Android only lets you raise the system prompt once. Spend that on a cold
/// launch, with no context, and a reflexive "don't allow" is permanent until
/// somebody goes digging in system settings, which nobody does. So this sheet
/// goes first: one sentence about what the notifications are for, and then the
/// real prompt only if they say yes. Declining here costs nothing, because the
/// system prompt is still unspent and the reminders screen can ask again.
Future<void> maybeAskForNotifications(BuildContext context) async {
  final notify = NotificationService.instance;
  if (await notify.hasBeenAsked()) return;
  if (await notify.enabled) return; // already granted, nothing to ask
  if (!context.mounted) return;

  final wants = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheet) => const _Primer(),
  );

  if (wants != true || !context.mounted) return;
  await notify.requestPermissions();
  if (context.mounted) await context.read<RemindersProvider>().resync();
}

class _Primer extends StatelessWidget {
  const _Primer();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration:
                  BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(OmIcons.byName('alarm'), color: c.primary, size: 24),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('can I remind you?',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Reminders and alarms you set need to reach you when the app is '
              'closed, which is most of the time. That is the only thing this '
              'is used for. Nothing else will ever buzz your phone.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: c.text2, height: 1.5),
            ),
            const SizedBox(height: AppSpacing.xl),
            OmTappable(
              onTap: () {
                Haptics.medium();
                Navigator.of(context).pop(true);
              },
              feedback: OmTapFeedback.none,
              pressedScale: 0.97,
              child: Container(
                height: 52,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: c.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text('yes, remind me',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: OmTappable(
                onTap: () {
                  Haptics.light();
                  Navigator.of(context).pop(false);
                },
                feedback: OmTapFeedback.none,
                pressedScale: 0.96,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text('not now',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(color: c.text2)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
