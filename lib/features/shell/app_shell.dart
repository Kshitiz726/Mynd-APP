import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/alerts_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import 'widgets/animated_index_stack.dart';
import '../../providers/focus_provider.dart';
import '../../providers/nav_provider.dart';
import '../../core/theme/app_colors.dart';
import '../../widgets/low_stim_filter.dart';
import '../../widgets/memory_autopilot.dart';
import '../community/community_screen.dart';
import '../focus/focus_active_screen.dart';
import '../focus/focus_room_screen.dart';
import '../focus/focus_screen.dart';
import '../schedule/schedule_screen.dart';
import '../../core/routes/app_routes.dart';
import '../../providers/focus_room_provider.dart';
import '../home/home_screen.dart';
import '../profile/profile_screen.dart';
import 'widgets/live_focus_pill.dart';
import 'widgets/om_nav_bar.dart';

/// The root authenticated shell: a persistent bottom nav over an [IndexedStack].
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Tab order must match [AppTab.values].
  static const List<Widget> _tabs = [
    HomeScreen(),
    ScheduleScreen(),
    CommunityScreen(),
    ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    // Subscribe to live chat app-wide so new messages reach the Chats list and
    // open conversations instantly, not just after reopening a chat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ChatProvider>().initRealtime();
      // Wire alerts app-wide so the bell's unread dot is live before the Alerts
      // tab is ever opened (new follow requests / comment alerts arrive over the
      // socket and bump the badge immediately).
      context.read<AlertsProvider>()
        ..init()
        ..load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    final focus = context.watch<FocusProvider>();
    // Focus is a route now, so the live pill is always worth showing in the shell.
    final showLivePill = focus.isActive;

    // Immersive surfaces hide the bottom nav so they read full-screen: a live
    // focus room, an open DM / group chat, and the keyboard being up.
    // A minimised room still counts as being *in* a room, but the app is
    // navigable again, so the nav bar comes back and the room waits behind a
    // pill instead of covering everything.
    final rooms = context.watch<FocusRoomProvider>();
    final inFocusRoom = rooms.roomVisible;
    final inChat = context.watch<ChatProvider>().activeConversationId != null;
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom != 0;
    final hideNav = inFocusRoom || inChat || keyboardUp;

    return MemoryAutopilot(
      child: LowStimFilter(
        child: Scaffold(
          // The nav bar is glass, and glass needs something behind it. Without
          // extendBody the Scaffold reserves a strip of its own background colour
          // under the bar, so the capsule floats on an opaque slab and the blur
          // has nothing to blur. Letting the body run underneath is what makes it
          // read as transparent; every screen already pads for it via
          // AppSpacing.screenBottom.
          extendBody: true,
          body: Stack(
            children: [
              SafeArea(
                bottom: false,
                child: Stack(
                  children: [
                    AnimatedIndexedStack(
                      index: nav.index,
                      reduceMotion: context.select<SettingsProvider, bool>(
                          (s) => s.reduceMotion),
                      children: _tabs,
                    ),
                    if (rooms.roomVisible)
                      const Positioned.fill(child: FocusRoomScreen()),
                  ],
                ),
              ),
              // One pill slot. A minimised room outranks a solo session, because
              // other people are waiting in it.
              if (rooms.minimised || showLivePill)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(
                        child: rooms.minimised
                            ? LiveFocusPill(
                                time: '${rooms.participantCount}',
                                modeName:
                                    rooms.activeRoom?.title ?? 'focus room',
                                onTap: rooms.restoreRoom,
                              )
                            : LiveFocusPill(
                                time: focus.timeString,
                                modeName: focus.activeMode!.name,
                                onTap: () => Navigator.of(context)
                                    .pushNamed(AppRoutes.focus),
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: hideNav
              ? null
              : OmNavBar(
                  current: nav.tab,
                  onSelect: nav.select,
                  onCreate: () => _showCreateSheet(context),
                  alertsUnread: context.watch<AlertsProvider>().alertsUnread,
                ),
        ),
      ),
    );
  }
}

/// The (+) sheet: the two things you *start* rather than browse to.
void _showCreateSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      final c = sheetContext.omColors;
      Widget option({
        required IconData icon,
        required String title,
        required String subtitle,
        required String route,
      }) {
        return ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: c.primary),
          ),
          title:
              Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
          subtitle:
              Text(subtitle, style: Theme.of(sheetContext).textTheme.bodySmall),
          onTap: () {
            Navigator.of(sheetContext).pop();
            Navigator.of(context).pushNamed(route);
          },
        );
      }

      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            option(
              icon: LucideIcons.timer,
              title: 'focus session',
              subtitle: 'sprint, pomodoro, deep work or flow',
              route: AppRoutes.focus,
            ),
            option(
              icon: LucideIcons.messageCircle,
              title: 'talk to your coach',
              subtitle: 'think out loud, get unstuck',
              route: AppRoutes.coach,
            ),
            const SizedBox(height: 12),
          ],
        ),
      );
    },
  );
}

/// A wrapper for the Focus tab to switch between the setup and active timer.
class FocusTabShell extends StatelessWidget {
  const FocusTabShell({super.key});

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusProvider>();
    return focus.isActive ? const FocusActiveScreen() : const FocusScreen();
  }
}
