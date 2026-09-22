import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/routes/app_routes.dart';
import '../../home/search/global_search_screen.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../providers/coach_provider.dart';
import '../../../widgets/om_push_drawer.dart';
import '../../../widgets/om_tappable.dart';

/// The chat's side drawer: the main thread, past side chats, and the way out
/// to everything that is not a conversation.
///
/// Chat is the home of the app now, which makes this drawer the app's only
/// remaining index. That is why the gear at the bottom is load-bearing rather
/// than decorative: Profile used to open from Home's avatar, and Home is no
/// longer a tab, so account deletion, blocked accounts and contact support all
/// hang off this one control.
///
/// Threads are the coach's existing history, shown as "side chats" instead of a
/// separate history screen. Same data, one less place to look.
///
/// It is a plain panel rather than a [Drawer] because [OmPushDrawer] reveals it
/// by sliding the app aside; there is nothing here to float or to dim.
class ChatDrawer extends StatelessWidget {
  const ChatDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final coach = context.watch<CoachProvider>();
    final threads = coach.threads;

    return Material(
      color: c.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'OurMynd',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),

            // The live conversation. Always here, always first.
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _MainChatRow(onTap: () => OmPushDrawer.of(context)?.close()),
            ),

            const SizedBox(height: AppSpacing.lg),
            Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Side chats',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: c.text2, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Icon(OmIcons.byName('archive'), size: 20, color: c.text2),
                ],
              ),
            ),

            Expanded(
              child: threads.isEmpty
                  ? const _NoSideChats()
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg),
                      itemCount: threads.length,
                      itemBuilder: (_, i) {
                        final t = threads[i];
                        return _ThreadRow(
                          title: t.title,
                          onTap: () async {
                            Haptics.light();
                            OmPushDrawer.of(context)?.close();
                            await coach.openThread(t.id);
                          },
                          onDelete: () => coach.deleteThread(t.id),
                        );
                      },
                    ),
            ),

            Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  // Everything that is not a conversation lives behind this.
                  _RoundIcon(
                    icon: 'settings',
                    tooltip: 'Settings and account',
                    onTap: () {
                      Haptics.light();
                      OmPushDrawer.of(context)?.close();
                      Navigator.of(context).pushNamed(AppRoutes.profile);
                    },
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: OmTappable(
                      onTap: () {
                        Haptics.light();
                        OmPushDrawer.of(context)?.close();
                        GlobalSearchScreen.open(context);
                      },
                      child: Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: c.surfaceAlt,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          children: [
                            Icon(OmIcons.byName('search'),
                                size: 19, color: c.text2),
                            const SizedBox(width: 10),
                            Text('Search',
                                style: TextStyle(
                                    color: c.text2,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  // Compose. The reference puts starting a new conversation
                  // here rather than at the top, next to the other verbs.
                  _RoundIcon(
                    icon: 'edit',
                    tooltip: 'New chat',
                    onTap: () async {
                      Haptics.light();
                      OmPushDrawer.of(context)?.close();
                      await coach.startNewChat();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MainChatRow extends StatelessWidget {
  const _MainChatRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          children: [
            Icon(OmIcons.byName('home'), size: 20, color: c.text),
            const SizedBox(width: 12),
            Text('Main chat',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.title,
    required this.onTap,
    required this.onDelete,
  });

  final String title;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.light,
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              Icon(OmIcons.byName('message'),
                  size: 18, color: c.text2),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              OmTappable(
                onTap: onDelete,
                feedback: OmTapFeedback.light,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(OmIcons.byName('trash'),
                      size: 16, color: c.text2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoSideChats extends StatelessWidget {
  const _NoSideChats();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(OmIcons.byName('message'), size: 30, color: c.text2),
            const SizedBox(height: 14),
            Text('Start a side chat',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Side chats are an optional way to organise your '
              'conversations by topic.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.text2, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({
    required this.icon,
    required this.onTap,
    required this.tooltip,
  });

  final String icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Tooltip(
      message: tooltip,
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.light,
        child: Container(
          width: 46,
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: c.surfaceAlt,
            shape: BoxShape.circle,
          ),
          child: Icon(OmIcons.byName(icon), size: 20, color: c.text),
        ),
      ),
    );
  }
}
