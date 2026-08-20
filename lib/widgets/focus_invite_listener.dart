import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_spacing.dart';
import '../core/services/realtime_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import '../core/utils/om_icons.dart';
import '../providers/focus_room_provider.dart';
import '../services/notification_service.dart';
import 'om_tappable.dart';

/// Makes "invite a friend" an invitation rather than a log entry.
///
/// The server has always pushed `body_doubling_invite` when someone asks you to
/// focus with them, and the app has always ignored it: the payload landed in
/// the activity history as a row you could not tap, so the invited half of the
/// feature did not exist. An invitation to work *right now* that you find later
/// by scrolling is not an invitation.
///
/// This sits in the shell for the whole signed-in session and does two things
/// when one arrives: raises a sheet if the app is in front of you, and posts a
/// real notification if it is not. Both land you in the same room.
class FocusInviteListener extends StatefulWidget {
  const FocusInviteListener({super.key, required this.child});

  final Widget child;

  @override
  State<FocusInviteListener> createState() => _FocusInviteListenerState();
}

class _FocusInviteListenerState extends State<FocusInviteListener> {
  final _rt = RealtimeService.instance;

  /// Rooms we have already offered. The socket can redeliver, and being asked
  /// the same question twice is worse than being asked late.
  final _seen = <String>{};

  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _rt.on('notification', _onNotification);
  }

  @override
  void dispose() {
    // Deliberately not `_rt.off('notification')`: the alerts provider listens
    // to the same event and removing the handler by name would take its
    // listener down with ours.
    super.dispose();
  }

  void _onNotification(Map<String, dynamic> d) {
    if (d['kind'] != 'body_doubling_invite') return;
    // The socket sends `{kind, payload}` - see pushNotification in the server's
    // services/notify.ts. `data` is the shape the REST history uses.
    final data = ((d['payload'] ?? d['data']) as Map?)?.cast<String, dynamic>() ?? d;
    final roomId = data['roomId'] as String?;
    if (roomId == null || !_seen.add(roomId)) return;
    final from = (data['fromName'] as String?) ?? 'someone';

    // Always post it. If the app is in front of them the sheet is what they
    // will act on, but a body-doubling invite is time-sensitive and the phone
    // being in a pocket is the normal case.
    NotificationService.instance.showNow(
      id: roomId.hashCode & 0x7fffffff,
      title: '$from wants to focus with you',
      body: 'tap to join them.',
    );

    if (!mounted || _showing) return;
    _showing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _showing = false;
        return;
      }
      final join = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        builder: (_) => _InviteSheet(from: from),
      );
      _showing = false;
      if (join == true && mounted) {
        context.read<FocusRoomProvider>().joinRoom(roomId);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _InviteSheet extends StatelessWidget {
  const _InviteSheet({required this.from});

  final String from;

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
              child: Icon(OmIcons.byName('users'), color: c.primary, size: 24),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('$from wants to focus with you',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'You work on your thing, they work on theirs, and neither of you '
              'is doing it alone. Nobody has to talk.',
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
                child: const Text('join them',
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
