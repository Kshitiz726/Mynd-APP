import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../providers/alerts_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../providers/community_provider.dart';
import '../../../providers/goal_provider.dart';
import '../../../providers/nav_provider.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/om_tappable.dart';

/// A single search hit, normalised across every source so the results list is
/// uniform regardless of what it points at.
class _Hit {
  _Hit({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String icon;
  final VoidCallback onTap;
}

/// One category of results - a labelled group, Android-Settings-search style.
class _Group {
  _Group({required this.label, required this.icon, required this.color, required this.hits});
  final String label;
  final String icon;
  final Color color;
  final List<_Hit> hits;
}

/// Global, in-app search - one box that looks across the whole app: tasks &
/// backlog, goals & their daily steps, notes, reminders, people & chats,
/// community posts and notifications. Results are grouped by category (like the
/// search inside Android Settings) so a single query surfaces everything.
class GlobalSearchScreen extends StatefulWidget {
  const GlobalSearchScreen({super.key});

  static Future<void> open(BuildContext context) {
    Haptics.light();
    return Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const GlobalSearchScreen(), fullscreenDialog: true),
    );
  }

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// Pops the search, then runs the destination action (tab switch / route).
  void _go(VoidCallback action) {
    Navigator.of(context).pop();
    action();
  }

  List<_Group> _results(BuildContext context) {
    final q = _q.trim().toLowerCase();
    if (q.isEmpty) return const [];
    bool m(String? s) => s != null && s.toLowerCase().contains(q);

    final c = context.omColors;
    final nav = context.read<NavProvider>();
    final tasks = context.read<TaskProvider>();
    final goals = context.read<GoalProvider>();
    final chat = context.read<ChatProvider>();
    final community = context.read<CommunityProvider>();
    final alerts = context.read<AlertsProvider>();

    final groups = <_Group>[];

    // ── Tasks & backlog ──
    final taskHits = <_Hit>[];
    for (final t in tasks.all.where((t) => !t.isChunk && m(t.title)).take(6)) {
      taskHits.add(_Hit(
        title: t.title,
        subtitle: t.done ? 'task · done' : 'task · ${t.energy.label} energy',
        icon: 'list',
        onTap: () => _go(() => nav.select(AppTab.today)),
      ));
    }
    if (taskHits.isNotEmpty) {
      groups.add(_Group(label: 'Tasks', icon: 'list', color: c.primary, hits: taskHits));
    }

    // ── Goals & daily steps ──
    final goalHits = <_Hit>[];
    for (final g in goals.goals) {
      if (m(g.title)) {
        goalHits.add(_Hit(
          title: g.title,
          subtitle: 'goal · ${(g.progress * 100).round()}% done',
          icon: 'target',
          onTap: () => _go(() => Navigator.of(context).pushNamed(AppRoutes.profile)),
        ));
      }
      for (final s in g.milestones.where((s) => m(s.title)).take(3)) {
        goalHits.add(_Hit(
          title: s.title,
          subtitle: 'step · ${g.title}',
          icon: 'activity',
          onTap: () => _go(() => nav.select(AppTab.today)),
        ));
      }
    }
    if (goalHits.isNotEmpty) {
      groups.add(_Group(label: 'Goals & steps', icon: 'target', color: c.accent, hits: goalHits.take(6).toList()));
    }

    // ── People & chats ──
    final chatHits = <_Hit>[];
    for (final cv in chat.conversations.where((cv) => m(cv.title) || m(cv.lastMessage)).take(5)) {
      chatHits.add(_Hit(
        title: cv.title,
        subtitle: cv.isGroup ? 'group chat' : 'direct message',
        icon: cv.isGroup ? 'users' : 'user',
        onTap: () => _go(() {
          nav.select(AppTab.community);
          chat.openChat(
            id: cv.id,
            title: cv.title,
            iconName: cv.isGroup ? (cv.iconName ?? 'users') : 'user',
            iconColor: cv.iconColor ?? cv.peerColor,
            isGroup: cv.isGroup,
          );
        }),
      ));
    }
    for (final g in [...chat.myGroups, ...chat.suggestedGroups].where((g) => m(g.name)).take(4)) {
      chatHits.add(_Hit(
        title: g.name,
        subtitle: 'group · ${g.membersLabel}',
        icon: 'users',
        onTap: () => _go(() => nav.select(AppTab.community)),
      ));
    }
    if (chatHits.isNotEmpty) {
      groups.add(_Group(label: 'People & chats', icon: 'message', color: c.flow, hits: chatHits.take(6).toList()));
    }

    // ── Community posts ──
    final postHits = <_Hit>[];
    for (final p in community.posts.where((p) => m(p.body) || m(p.authorName)).take(5)) {
      postHits.add(_Hit(
        title: p.body,
        subtitle: 'post · ${p.authorName}',
        icon: 'message',
        onTap: () => _go(() => nav.select(AppTab.community)),
      ));
    }
    if (postHits.isNotEmpty) {
      groups.add(_Group(label: 'Community', icon: 'users', color: c.success, hits: postHits));
    }

    // ── Notifications & follow requests ──
    final notifHits = <_Hit>[];
    for (final req in alerts.requests.where((r) => m(r.displayName)).take(3)) {
      notifHits.add(_Hit(
        title: '${req.displayName} wants to follow you',
        subtitle: 'follow request',
        icon: 'userPlus',
        onTap: () => _go(() => nav.select(AppTab.alerts)),
      ));
    }
    for (final n in alerts.allNotifications.where((n) {
      final body = n.payload['name'] ?? n.payload['body'] ?? n.kind;
      return m(body?.toString()) || m(n.kind);
    }).take(4)) {
      notifHits.add(_Hit(
        title: (n.payload['name'] ?? n.payload['body'] ?? n.kind).toString(),
        subtitle: 'notification',
        icon: 'bell',
        onTap: () => _go(() => nav.select(AppTab.alerts)),
      ));
    }
    if (notifHits.isNotEmpty) {
      groups.add(_Group(label: 'Notifications', icon: 'bell', color: c.attention, hits: notifHits));
    }

    // ── Notebook & reminders (the in-app shortcuts) ──
    final placeHits = <_Hit>[];
    if (m('notes') || m('notebook') || m('note')) {
      placeHits.add(_Hit(
        title: 'Notebook',
        subtitle: 'your notes & brain dumps',
        icon: 'file-text',
        onTap: () => _go(() => Navigator.of(context).pushNamed(AppRoutes.notes)),
      ));
    }
    if (m('reminder') || m('reminders') || m('alarm')) {
      placeHits.add(_Hit(
        title: 'Reminders',
        subtitle: 'gentle nudges & cadences',
        icon: 'alarm',
        onTap: () => _go(() => Navigator.of(context).pushNamed(AppRoutes.reminders)),
      ));
    }
    if (placeHits.isNotEmpty) {
      groups.add(_Group(label: 'In the app', icon: 'search', color: c.text2, hits: placeHits));
    }

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final groups = _results(context);
    final hasQuery = _q.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Search bar.
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: Row(
                children: [
                  OmTappable(
                    onTap: () => Navigator.of(context).pop(),
                    pressedScale: 0.9,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(OmIcons.byName('back'), color: c.text),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 44,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Icon(OmIcons.byName('search'), size: 18, color: c.text2),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              autofocus: true,
                              textInputAction: TextInputAction.search,
                              cursorColor: c.primary,
                              onChanged: (v) => setState(() => _q = v),
                              decoration: InputDecoration(
                                isCollapsed: true,
                                border: InputBorder.none,
                                hintText: 'Search tasks, goals, chats, notes…',
                                hintStyle:
                                    Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2),
                              ),
                            ),
                          ),
                          if (hasQuery)
                            OmTappable(
                              onTap: () => setState(() {
                                _ctrl.clear();
                                _q = '';
                              }),
                              child: Icon(OmIcons.byName('close'), size: 18, color: c.text2),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: !hasQuery
                  ? _Hint()
                  : groups.isEmpty
                      ? _Empty(query: _q)
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(
                              AppSpacing.screenH, 4, AppSpacing.screenH, AppSpacing.screenBottom),
                          children: [
                            for (final g in groups) _GroupSection(group: g),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupSection extends StatelessWidget {
  const _GroupSection({required this.group});
  final _Group group;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Icon(OmIcons.byName(group.icon), size: 14, color: group.color),
              const SizedBox(width: 7),
              Text(group.label.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: group.color,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        fontSize: 10.5,
                      )),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: c.border.withValues(alpha: 0.8)),
          ),
          child: Column(
            children: [
              for (var i = 0; i < group.hits.length; i++) ...[
                if (i > 0)
                  Divider(height: 1, thickness: 1, color: c.border.withValues(alpha: 0.6), indent: 60),
                _HitRow(hit: group.hits[i], color: group.color),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _HitRow extends StatelessWidget {
  const _HitRow({required this.hit, required this.color});
  final _Hit hit;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: hit.onTap,
      feedback: OmTapFeedback.light,
      pressedScale: 0.98,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(OmIcons.byName(hit.icon), size: 18, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(hit.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontSize: 14.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 1),
                  Text(hit.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 12)),
                ],
              ),
            ),
            Icon(OmIcons.byName('chevR'), size: 16, color: c.text2),
          ],
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(OmIcons.byName('search'), size: 40, color: c.text2.withValues(alpha: 0.5)),
            const SizedBox(height: 14),
            Text('Search across everything',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('tasks, goals, notes, reminders, chats & community - all in one place',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.query});
  final String query;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text('No results for “${query.trim()}”',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
