import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/community/chat_models.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/nav_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_card.dart';
import '../../widgets/om_tappable.dart';
import '../../widgets/om_top_bar.dart';
import '../community/chat_screen.dart';

/// "alerts" - deliberately narrow: only the two things that need *your* reaction,
/// follow requests and comments on your posts. Everything else (reminders, room
/// joins, sessions, messages) lives in the "you" tab's activity history.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    // Load on open, but DON'T auto-clear - unread alerts stay highlighted until
    // the user taps "mark all read" (so the badge + the button both mean something).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AlertsProvider>()
        ..init()
        ..load();
    });
  }

  Color _hex(String? s, Color fallback) {
    if (s == null) return fallback;
    var h = s.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  Future<void> _accept(FollowRequest req) async {
    Haptics.success();
    final cid = await context.read<AlertsProvider>().accept(req);
    if (!mounted) return;
    if (cid != null) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(conversationId: cid, title: req.displayName, isGroup: false),
      ));
    } else {
      Toast.show(context, "You're now connected");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final alerts = context.watch<AlertsProvider>();
    final requests = alerts.requests;
    final comments = alerts.commentNotifications;
    final empty = requests.isEmpty && comments.isEmpty;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH, AppSpacing.screenTop, AppSpacing.screenH, 100),
        children: [
          OmTopBar(
            title: 'alerts',
            subtitle: _summary(requests.length, comments.length),
          ),

          if (alerts.alertsUnread > 0) ...[
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: OmTappable(
                onTap: () {
                  Haptics.medium();
                  context.read<AlertsProvider>().markAllRead();
                },
                pressedScale: 0.96,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(OmIcons.byName('checkCheck'), size: 16, color: c.text2),
                      const SizedBox(width: 8),
                      Text('Mark all as read',
                          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: c.text, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ] else
            const SizedBox(height: AppSpacing.lg),

          if (empty)
            _EmptyState(loading: alerts.loading)
          else ...[
            // ── Follow requests ──
            if (requests.isNotEmpty) ...[
              _SectionLabel(icon: 'userPlus', label: 'follow requests', count: requests.length),
              const SizedBox(height: AppSpacing.sm),
              for (final req in requests) ...[
                _RequestCard(
                  req: req,
                  color: _hex(req.avatarColor, c.primary),
                  onAccept: () => _accept(req),
                  onReject: () {
                    Haptics.light();
                    context.read<AlertsProvider>().reject(req);
                  },
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: AppSpacing.lg),
            ],

            // ── Comments on your posts ──
            if (comments.isNotEmpty) ...[
              _SectionLabel(
                  icon: 'message', label: 'comments on your posts', count: comments.length),
              const SizedBox(height: AppSpacing.sm),
              for (final n in comments) ...[
                _CommentCard(
                  notification: n,
                  onTap: () {
                    Haptics.select();
                    context.read<AlertsProvider>().markAllRead();
                    context.read<NavProvider>().select(AppTab.community);
                  },
                ),
                const SizedBox(height: 10),
              ],
            ],
          ],
        ],
      ),
    );
  }

  String _summary(int reqs, int comments) {
    if (reqs == 0 && comments == 0) return 'follow requests & comments';
    final parts = <String>[];
    if (reqs > 0) parts.add('$reqs follow ${reqs == 1 ? 'request' : 'requests'}');
    if (comments > 0) parts.add('$comments ${comments == 1 ? 'comment' : 'comments'}');
    return parts.join(' · ');
  }
}

/// A relative "2m ago / 3h ago / Apr 4" stamp for alert rows.
String relativeTime(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${months[t.month - 1]} ${t.day}';
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.icon, required this.label, required this.count});
  final String icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Row(
      children: [
        Icon(OmIcons.byName(icon), size: 16, color: c.text2),
        const SizedBox(width: 8),
        Text(label, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: c.primaryTint,
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text('$count',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: c.primary, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.loading});
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
              child: Icon(OmIcons.byName(loading ? 'bell' : 'check'), size: 30, color: c.primary),
            ),
            const SizedBox(height: 16),
            Text(loading ? 'loading…' : "you're all caught up",
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              loading ? '' : 'follow requests and post comments show up here',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    required this.req,
    required this.color,
    required this.onAccept,
    required this.onReject,
  });

  final FollowRequest req;
  final Color color;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(
            children: [
              OmAvatar(userId: req.userId, fallbackInitial: req.initial, fallbackColor: color, size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(req.displayName,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15)),
                    const SizedBox(height: 2),
                    Text('wants to follow you · ${relativeTime(req.createdAt)}',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OmTappable(
                  onTap: onReject,
                  pressedScale: 0.96,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(color: c.border),
                    ),
                    child: Text('Decline',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: c.text2, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OmTappable(
                  onTap: onAccept,
                  pressedScale: 0.96,
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    decoration: BoxDecoration(
                      gradient: c.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('Accept',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  const _CommentCard({required this.notification, required this.onTap});
  final AppNotification notification;
  final VoidCallback onTap;

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
    final p = notification.payload;
    final name = (p['name'] ?? 'Someone') as String;
    final userId = p['userId'] as String?;
    final preview = (p['preview'] ?? '') as String;
    final unread = !notification.read;

    return OmTappable(
      onTap: onTap,
      pressedScale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: unread ? c.primaryTint : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: unread ? c.primary.withValues(alpha: 0.25) : c.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                OmAvatar(
                  userId: userId ?? name,
                  fallbackInitial: name.isEmpty ? '?' : name.substring(0, 1),
                  fallbackColor: _hex(p['color'] as String?, c.primary),
                  size: 44,
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: c.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.surface, width: 2),
                    ),
                    child: Icon(OmIcons.byName('message'), size: 11, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.bodyMedium,
                      children: [
                        TextSpan(
                            text: name,
                            style: const TextStyle(fontWeight: FontWeight.w800)),
                        const TextSpan(text: ' commented on your post'),
                      ],
                    ),
                  ),
                  if (preview.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('“$preview”',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontStyle: FontStyle.italic, color: c.text2)),
                  ],
                  const SizedBox(height: 4),
                  Text(relativeTime(notification.createdAt),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
                ],
              ),
            ),
            if (unread)
              Container(
                margin: const EdgeInsets.only(left: 6, top: 4),
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle),
              ),
          ],
        ),
      ),
    );
  }
}
