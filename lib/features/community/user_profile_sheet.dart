import 'package:flutter/material.dart';

import '../../core/services/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/community/chat_models.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_tappable.dart';
import 'moderation_sheet.dart';

/// Bottom sheet shown when tapping a member in a group chat, or the person
/// matchmaking has just paired you with. Lets you send a follow request; once
/// accepted (handled in Alerts) a DM unlocks.
///
/// It also carries report and block. This is the one screen in the app that is
/// only ever about another human being, which makes it the place somebody
/// looks when they want that person gone - rather than having to remember
/// which surface they first met them on. Guideline 1.2 asks for the action to
/// be available wherever the person is; putting it here means every caller
/// gets it without having to wire it up again.
class UserProfileSheet extends StatefulWidget {
  const UserProfileSheet({super.key, required this.userId, this.fallbackName});

  final String userId;
  final String? fallbackName;

  /// True when the sheet was closed because this person was blocked, so the
  /// caller can drop them from whatever it is showing.
  static Future<bool> show(BuildContext context, String userId, {String? fallbackName}) async {
    Haptics.select();
    final blocked = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => UserProfileSheet(userId: userId, fallbackName: fallbackName),
    );
    return blocked ?? false;
  }

  @override
  State<UserProfileSheet> createState() => _UserProfileSheetState();
}

class _UserProfileSheetState extends State<UserProfileSheet> {
  UserProfile? _profile;
  bool _loading = true;
  bool _sending = false;
  String? _localStatus; // overrides after we send a request optimistically

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await ApiClient.instance.fetchUserProfile(widget.userId);
      if (mounted) setState(() => _profile = p);
    } catch (_) {
      // leave _profile null → minimal sheet with the fallback name
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _follow() async {
    // Optimistic: flip the button to "Follow Request Sent" immediately so the
    // user sees the result without any refresh, then fire the request.
    setState(() {
      _sending = true;
      _localStatus = 'pending';
    });
    Haptics.success();
    try {
      await ApiClient.instance.sendFriendRequest(widget.userId);
      if (mounted) Toast.show(context, 'Follow request sent');
    } catch (_) {
      if (mounted) {
        setState(() => _localStatus = null); // roll back on failure
        Toast.show(context, "Couldn't send request");
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Color _hex(String? s, Color fallback) {
    if (s == null) return fallback;
    var h = s.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final p = _profile;
    final name = p?.displayName ?? widget.fallbackName ?? 'Member';
    final initial = p?.initial ?? (name.isNotEmpty ? name[0].toUpperCase() : '?');
    final color = _hex(p?.avatarColor, c.primary);
    final status = _localStatus ?? p?.friendStatus;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 22),
          OmAvatar(
            userId: widget.userId,
            fallbackInitial: initial,
            fallbackColor: color,
            size: 76,
          ),
          const SizedBox(height: 14),
          Text(name, style: Theme.of(context).textTheme.titleLarge),
          // Only show a handle if it's a real public handle - never an email
          // (defence-in-depth; the server already withholds the email).
          if (p?.handle != null && !p!.handle!.contains('@')) ...[
            const SizedBox(height: 2),
            Text(p.handle!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 22),
          if (_loading)
            const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(strokeWidth: 2))
          else ...[
            _action(context, p, status),
            // Not offered on your own profile - there is nobody to report.
            if (p?.isMe != true) ...[
              const SizedBox(height: 14),
              OmTappable(
                onTap: () => _reportOrBlock(name),
                feedback: OmTapFeedback.light,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: Text('Report or block',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: c.text2,
                            decoration: TextDecoration.underline,
                          )),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _reportOrBlock(String name) async {
    final blocked = await showModerationSheet(
      context,
      targetType: 'user',
      targetId: widget.userId,
      authorId: widget.userId,
      authorName: name,
    );
    // Closing on a block is the point: the sheet is a page about somebody you
    // have just decided not to see, and leaving it open is leaving them on
    // screen. The flag travels back up so the list behind it can lose them too.
    if (blocked && mounted) Navigator.of(context).pop(true);
  }

  Widget _action(BuildContext context, UserProfile? p, String? status) {
    if (p?.isMe == true) {
      return const SizedBox.shrink();
    }
    // Accepted → mutual follow. Pending → request already sent (this is the
    // instant, no-refresh state we flip to the moment they tap Follow).
    if (status == 'accepted') {
      return _pill(context, icon: 'userCheck', label: 'Following', filled: false, onTap: null);
    }
    if (status == 'pending') {
      return _pill(context, icon: 'check', label: 'Follow Request Sent', filled: false, onTap: null);
    }
    return _pill(
      context,
      icon: 'userPlus',
      label: _sending ? 'Sending…' : 'Follow',
      filled: true,
      onTap: _sending ? null : _follow,
    );
  }

  Widget _pill(BuildContext context,
      {required String icon, required String label, required bool filled, VoidCallback? onTap}) {
    final c = context.omColors;
    final child = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 15),
      decoration: BoxDecoration(
        gradient: filled ? c.brandGradient : null,
        color: filled ? null : c.surfaceAlt,
        borderRadius: BorderRadius.circular(16),
        border: filled ? null : Border.all(color: c.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(OmIcons.byName(icon), size: 18, color: filled ? Colors.white : c.text2),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: filled ? Colors.white : c.text, fontWeight: FontWeight.w700, fontSize: 15)),
        ],
      ),
    );
    return onTap == null ? child : OmTappable(onTap: onTap, child: child);
  }
}
