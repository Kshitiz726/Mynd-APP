import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/community/blocked_user.dart';
import '../../widgets/om_tappable.dart';

/// The people you have blocked, and the way back.
///
/// A block has to be reversible, and it has to be reversible somewhere you can
/// find without needing to meet the person again. Blocking them from a post
/// works precisely because you never see their posts afterwards - which means
/// the post is the one place the unblock button cannot live.
class BlockedAccountsScreen extends StatefulWidget {
  const BlockedAccountsScreen({super.key});

  @override
  State<BlockedAccountsScreen> createState() => _BlockedAccountsScreenState();
}

class _BlockedAccountsScreenState extends State<BlockedAccountsScreen> {
  List<BlockedUser>? _blocked;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await ApiClient.instance.fetchBlocked();
      if (mounted) setState(() => _blocked = list);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your blocked list.');
    }
  }

  Future<void> _unblock(BlockedUser u) async {
    Haptics.light();
    // Removed first, restored if the server disagrees. Unblocking is a small,
    // reversible thing and waiting on a round trip to see it happen makes the
    // button feel broken.
    final before = _blocked;
    setState(() => _blocked = [..._blocked!]..removeWhere((b) => b.id == u.id));
    try {
      await ApiClient.instance.unblockUser(u.id);
    } catch (_) {
      if (!mounted) return;
      setState(() => _blocked = before);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not unblock ${u.displayName}.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final blocked = _blocked;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('Blocked accounts'),
      ),
      body: SafeArea(
        child: switch ((blocked, _error)) {
          (_, final String e) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(e,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.text2)),
              ),
            ),
          (null, _) => const Center(child: CircularProgressIndicator()),
          (final List<BlockedUser> list, _) when list.isEmpty => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text(
                  "You haven't blocked anyone.\n"
                  'Tap someone to open their profile - in a focus room, or when '
                  'body doubling pairs you with them - and choose Report or '
                  'block. They will show up here, and you can undo it here too.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.text2, height: 1.45),
                ),
              ),
            ),
          (final List<BlockedUser> list, _) => ListView.builder(
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: list.length,
              itemBuilder: (_, i) => _BlockedRow(
                user: list[i],
                onUnblock: () => _unblock(list[i]),
              ),
            ),
        },
      ),
    );
  }
}

class _BlockedRow extends StatelessWidget {
  const _BlockedRow({required this.user, required this.onUnblock});

  final BlockedUser user;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border.withValues(alpha: 0.7)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(user.initial,
                style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700)),
                if (user.handle.isNotEmpty)
                  Text(user.handle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: c.text2)),
              ],
            ),
          ),
          OmTappable(
            onTap: onUnblock,
            feedback: OmTapFeedback.light,
            pressedScale: 0.96,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(OmIcons.byName('userCheck'),
                      size: 16, color: c.primary),
                  const SizedBox(width: 6),
                  Text('Unblock',
                      style: TextStyle(
                          color: c.primary, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
