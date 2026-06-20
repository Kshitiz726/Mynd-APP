import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/alerts_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import 'widgets/animated_index_stack.dart';
import '../../providers/focus_provider.dart';
import '../../providers/nav_provider.dart';
import '../../widgets/low_stim_filter.dart';
import '../coach/coach_screen.dart';
import '../community/community_screen.dart';
import '../focus/focus_active_screen.dart';
import '../focus/focus_room_screen.dart';
import '../focus/focus_screen.dart';
import '../../providers/focus_room_provider.dart';
import '../home/home_screen.dart';
import '../notifications/notifications_screen.dart';
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
    FocusTabShell(),
    CommunityScreen(),
    NotificationsScreen(),
    CoachScreen(),
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
    final showLivePill = focus.isActive && nav.tab != AppTab.focus;

    // Immersive surfaces hide the bottom nav so they read full-screen: a live
    // focus room, an open DM / group chat, and the keyboard being up.
    final inFocusRoom = context.watch<FocusRoomProvider>().activeRoomId != null;
    final inChat = context.watch<ChatProvider>().activeConversationId != null;
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom != 0;
    final hideNav = inFocusRoom ||
        inChat ||
        keyboardUp ||
        nav.tab == AppTab.coach || // Coach is a focused Messenger-style view
        (focus.isActive && nav.tab == AppTab.focus);

    return LowStimFilter(
      child: Scaffold(
        extendBody: false, // Turn off extendBody so we control padding manually
        body: Stack(
          children: [
            SafeArea(
              bottom: false,
              child: Stack(
                children: [
                  AnimatedIndexedStack(
                    index: nav.index,
                    reduceMotion: context.select<SettingsProvider, bool>((s) => s.reduceMotion),
                    children: _tabs,
                  ),
                  if (context.watch<FocusRoomProvider>().activeRoomId != null)
                    const Positioned.fill(child: FocusRoomScreen()),
                ],
              ),
            ),
            if (showLivePill)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(
                      child: LiveFocusPill(
                        time: focus.timeString,
                        modeName: focus.activeMode!.name,
                        onTap: () => nav.select(AppTab.focus),
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
                alertsUnread: context.watch<AlertsProvider>().alertsUnread,
              ),
      ),
    );
  }
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
