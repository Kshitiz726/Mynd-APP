import 'dart:async';
import 'package:flutter/material.dart';
// Lucide only fed the parked (+) create sheet; nav-tab icons live on AppTab.
// import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../providers/alerts_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import 'widgets/animated_index_stack.dart';
import '../../providers/feed_provider.dart';
import '../../providers/focus_provider.dart';
import '../../providers/nav_provider.dart';
// app_colors only served the parked (+) create sheet.
// import '../../core/theme/app_colors.dart';
import '../../widgets/low_stim_filter.dart';
import '../../widgets/memory_autopilot.dart';
import '../../widgets/notification_primer.dart';
import '../../widgets/om_push_drawer.dart';
// Community and Profile are parked as tabs (see _tabs); imports kept commented
// so the wiring is one line away when they come back.
// import '../community/community_screen.dart';
// import '../profile/profile_screen.dart';
import '../coach/coach_screen.dart';
import '../coach/widgets/chat_drawer.dart';
import '../focus/focus_active_screen.dart';
import '../focus/focus_room_screen.dart';
import '../focus/focus_screen.dart';
import '../schedule/schedule_screen.dart';
import '../../core/routes/app_routes.dart';
import '../../providers/focus_room_provider.dart';
import '../../widgets/focus_invite_listener.dart';
import '../feed/feed_screen.dart';
import 'widgets/live_focus_pill.dart';
import 'widgets/om_nav_bar.dart';
import '../home/widgets/quick_add_sheet.dart';
import '../../core/services/mail_watch.dart';
import '../../core/services/server_directory.dart';

/// The root authenticated shell: a persistent bottom nav over an [IndexedStack].
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back is the only reliable moment this app gets. iOS will not run
    // it on a schedule in the background, so anything that was meant to happen
    // while it was away, a queued message whose time came or mail that landed,
    // is caught up here.
    if (state == AppLifecycleState.resumed) {
      unawaited(MailWatch.instance.onResumed());
      // Also the moment to notice the server moved while the app was away.
      // Throttled inside, so a user who switches apps constantly does not
      // re-read the file every time.
      unawaited(ServerDirectory.instance.refreshIfStale());
    }
  }

  /// Tab order must match [AppTab.values]: chat · feed · schedule · focus.
  ///
  /// Chat is first and is where the app opens: it is the thing people come back
  /// for, and putting a dashboard in front of it made them navigate to reach it.
  /// Home is parked as a result, its pieces redistributed rather than dropped -
  /// the day's line, the one actionable task and the mood check-in are the top
  /// of Feed, and goals sit with the rest of the plan on Schedule.
  ///
  /// Profile moved with it, to the chat drawer's gear. Home's avatar was the
  /// only route to account deletion, blocked accounts and support, so parking
  /// the tab without moving that first would have taken three App Store
  /// requirements off the map.
  static const List<Widget> _tabs = [
    CoachScreen(),
    FeedScreen(),
    ScheduleScreen(),
    FocusTabShell(),
    // HomeScreen(),      -> its pieces live on Feed and Schedule now
    // CommunityScreen(),
    // ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      // The Feed is written, not fetched, and writing takes a few seconds.
      // Starting it here rather than in the tab's own initState means it is
      // ready when somebody opens it instead of making them watch it compose.
      // Rate limited to one edition per day-part, so this is at most a handful
      // of calls a day however often the app is opened.
      context.read<FeedProvider>().load();
      _askForNotifications();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// The one permission this app actually needs, asked for once, early, and out
  /// of the way of anything else on screen.
  ///
  /// Home may be showing the mood check-in on the same frame, and two sheets
  /// racing for the bottom of the screen means one of them is dismissed by
  /// accident. So this waits for the shell to be the top route again before it
  /// says anything, and gives up quietly if the user is busy.
  Future<void> _askForNotifications() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      if (!Navigator.of(context).canPop()) {
        if (mounted) await maybeAskForNotifications(context);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final nav = context.watch<NavProvider>();
    final focus = context.watch<FocusProvider>();
    // The live pill is a way *back* to a running session from elsewhere. On the
    // Focus tab itself the timer is already on screen, so the pill there is just
    // a second clock floating over the first - show it only off the Focus tab.
    final showLivePill = focus.isActive && nav.tab != AppTab.focus;

    // Immersive surfaces hide the bottom nav so they read full-screen: a live
    // focus room, an open DM / group chat, the coach, and the keyboard being up.
    // A minimised room still counts as being *in* a room, but the app is
    // navigable again, so the nav bar comes back and the room waits behind a
    // pill instead of covering everything.
    final rooms = context.watch<FocusRoomProvider>();
    final inFocusRoom = rooms.roomVisible;
    final inChat = context.watch<ChatProvider>().activeConversationId != null;
    final keyboardUp = MediaQuery.of(context).viewInsets.bottom != 0;
    // A running solo session is immersive too: on the Focus tab the timer owns
    // the screen and the only way out is its own back button (which confirms).
    final inFocusSession = focus.isActive && nav.tab == AppTab.focus;
    // The coach used to hide the bar: it was a destination you navigated to,
    // it owned the screen, and its own back arrow was the way out.
    //
    // It is the first tab now, and the app opens on it, so hiding the bar there
    // means launching with no navigation at all and no way to reach Feed,
    // Schedule or Focus. The reference design keeps the bar on the chat screen
    // for exactly this reason. The keyboard case below still hides it, which is
    // what was actually costing thumb-room while typing.
    final hideNav = inFocusRoom || inChat || keyboardUp || inFocusSession;

    return MemoryAutopilot(
      child: FocusInviteListener(
        child: LowStimFilter(
        // The chat's index lives out here rather than inside CoachScreen
        // because the panel pushes the whole app aside, bottom bar included,
        // and the bottom bar belongs to this Scaffold. An edge drag only opens
        // it on the chat tab - elsewhere a horizontal swipe means the week
        // rail or a carousel, and stealing that would be worse than the panel
        // being one button away.
        child: OmPushDrawer(
          panel: const ChatDrawer(),
          dragEnabled: nav.tab == AppTab.coach && !inFocusRoom && !inChat,
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
              //
              // The pill is only ever a way *back* to a session from somewhere
              // else, so it has no business on top of that session. It is hidden
              // on the Focus tab, where the timer is already the screen, and on
              // the focus room, which is a full-screen overlay that can sit over
              // any tab - so without this a running solo timer put a spinner and
              // a clock on top of the room for as long as both were going.
              if (!inFocusRoom &&
                  ((rooms.minimised && nav.tab != AppTab.focus) || showLivePill))
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
          // One rule, one bar.
          //
          // The coach used to get its own branch here, keeping the bar on
          // screen whenever a PuterService stream said you were not signed in
          // to Puter. The coach talks to our own server now and that stream is
          // permanently false, so the special case did the exact opposite of
          // what it was written for: the bar was always up on the one tab
          // designed not to have one.
          bottomNavigationBar: hideNav
              ? null
              : OmNavBar(
                  current: nav.tab,
                  onSelect: nav.select,
                  onAdd: () => showQuickAddSheet(context),
                ),
          ),
        ),
        ),
      ),
    );
  }
}

// The (+) create sheet is parked along with the centre button: focus and the
// coach are their own tabs now, so there is nothing left to "start" from here.
// Kept (commented) in case the (+) ever comes back.
/*
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
*/

/// A wrapper for the Focus tab to switch between the setup and active timer.
class FocusTabShell extends StatelessWidget {
  const FocusTabShell({super.key});

  @override
  Widget build(BuildContext context) {
    final focus = context.watch<FocusProvider>();
    return focus.isActive ? const FocusActiveScreen() : const FocusScreen();
  }
}
