import 'package:flutter/material.dart';

import '../../core/services/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/community/chat_models.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_tappable.dart';
import 'user_profile_sheet.dart';

/// Reveals everyone in a group room - their avatar + username. Tapping a member
/// (other than yourself) opens their profile sheet so you can follow them.
class GroupMembersSheet extends StatefulWidget {
  const GroupMembersSheet({super.key, required this.conversationId, required this.title});

  final String conversationId;
  final String title;

  static Future<void> show(BuildContext context, String conversationId, String title) {
    Haptics.select();
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => GroupMembersSheet(conversationId: conversationId, title: title),
    );
  }

  @override
  State<GroupMembersSheet> createState() => _GroupMembersSheetState();
}

class _GroupMembersSheetState extends State<GroupMembersSheet> {
  List<ConversationMember>? _members;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final m = await ApiClient.instance.fetchConversationMembers(widget.conversationId);
      if (mounted) setState(() => _members = m);
    } catch (_) {
      // leave null → empty state
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final members = _members ?? const [];

    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(OmIcons.byName('users'), size: 20, color: c.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text('${widget.title} · members',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (!_loading)
                Text('${members.length}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.text2)),
            ],
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (members.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text('No members to show',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: members.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (context, i) {
                  final m = members[i];
                  return OmTappable(
                    onTap: m.isMe
                        ? null
                        : () => UserProfileSheet.show(context, m.id, fallbackName: m.displayName),
                    feedback: m.isMe ? OmTapFeedback.none : OmTapFeedback.light,
                    pressedScale: m.isMe ? 1 : 0.98,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          OmAvatar(
                            userId: m.id,
                            fallbackInitial: m.initial,
                            fallbackColor: _hex(m.avatarColor, c.primary),
                            size: 44,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              m.isMe ? '${m.displayName} (you)' : m.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15),
                            ),
                          ),
                          if (!m.isMe)
                            Icon(OmIcons.byName('chevR'), size: 18, color: c.text2),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
