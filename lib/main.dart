import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/routes/app_router.dart';
import 'core/routes/app_routes.dart';
import 'core/services/api_client.dart';
import 'core/services/api_config.dart';
import 'core/services/alarm_service.dart';
import 'core/services/coach_memory_service.dart';
import 'core/services/realtime_service.dart';
import 'core/services/session_store.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/om_scroll_behavior.dart';
import 'features/splash/splash_screen.dart';
import 'providers/alerts_provider.dart';
import 'providers/alarms_provider.dart';
import 'providers/coach_provider.dart';
import 'providers/community_provider.dart';
import 'providers/chat_provider.dart';
import 'providers/energy_provider.dart';
import 'providers/focus_provider.dart';
import 'providers/focus_room_provider.dart';
import 'providers/goal_provider.dart';
import 'providers/habit_provider.dart';
import 'providers/memory_provider.dart';
import 'providers/mood_provider.dart';
import 'providers/nav_provider.dart';
import 'providers/premium_provider.dart';
import 'providers/reminders_provider.dart';
import 'providers/notes_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/streak_provider.dart';
import 'providers/task_provider.dart';
import 'services/notification_service.dart';
import 'widgets/puter_host.dart';

/// Root navigator key - lets the app-wide [PuterHost] present Puter's one-time
/// sign-in popup over whatever screen is showing.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Demo mode - enable with `--dart-define=OURMYND_DEMO=true`.
///
/// Boots straight into the shell, skipping Google sign-in, and leaves realtime
/// disconnected. This exists for environments where neither the backend nor an
/// iOS OAuth client is reachable - chiefly a cloud iOS Simulator, where sign-in
/// is impossible and the login screen would be a dead end.
///
/// Today/goals/tasks/energy/settings are backed by `shared_preferences`, so they
/// work fully offline. The server-backed tabs (Community, Focus rooms, Coach,
/// Alerts) will be empty or error - that is expected here, not a bug.
///
/// Defaults to false, so release builds are unaffected.
const kDemoMode = bool.fromEnvironment('OURMYND_DEMO');

void main() async {
  // Stamped before anything else so the launch screen can measure its own
  // duration from the true start of the app rather than from the moment it is
  // built - everything below this line happens while the system splash is
  // still up, and should be overlapped by the entrance, not added to it.
  final bootAt = DateTime.now();
  WidgetsFlutterBinding.ensureInitialized();

  // Coach memory (parked thoughts + rolling summary) is app-wide; load it once
  // up front so parking a thought outside the coach screen merges, not clobbers.
  await CoachMemoryService.instance.init();

  // Auto-login: if a session was saved, restore it and reconnect realtime so we
  // land straight in the shell. Otherwise start at the login screen.
  final hasSession = await SessionStore.restore();
  // Demo mode has no session to authenticate the socket with, and an
  // unreachable server would just retry-storm in the background.
  if (hasSession && !kDemoMode) {
    RealtimeService.instance.connect();
  }

  AlarmService.instance.init();
  // Channels and the timezone database, up front. The permission itself is
  // asked for on the first screen instead, where there is room to say why.
  await NotificationService.instance.init();

  runApp(OurMyndApp(
    initialRoute: (hasSession || kDemoMode) ? AppRoutes.shell : AppRoutes.login,
    bootAt: bootAt,
  ));
}

class OurMyndApp extends StatelessWidget {
  const OurMyndApp({
    super.key,
    required this.initialRoute,
    required this.bootAt,
  });

  final String initialRoute;

  /// When main() began. Handed to the launch screen so it can time itself.
  final DateTime bootAt;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        // Subscription entitlement (Stripe). Gates premium-only features and
        // drives the paywall checkout. Refreshed after sign-in / on the paywall.
        ChangeNotifierProvider(create: (_) => PremiumProvider()..refresh()),
        ChangeNotifierProvider(create: (_) => NavProvider()),
        ChangeNotifierProvider(create: (_) => EnergyProvider()),
        ChangeNotifierProvider(create: (_) => TaskProvider()),
        ChangeNotifierProvider(create: (_) => HabitProvider()),
        ChangeNotifierProvider(create: (_) => FocusProvider()),
        // Backend-backed Community feed + live Focus Rooms (Socket.IO/LiveKit).
        ChangeNotifierProvider(create: (_) => CommunityProvider()),
        ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
        ChangeNotifierProvider(create: (_) => ChatProvider()),
        ChangeNotifierProvider(create: (_) => AlertsProvider()),
        ChangeNotifierProvider(create: (_) => AlarmsProvider()),
        // What the app knows about the user: written by the AI, editable by
        // them, and read back into every coach reply.
        ChangeNotifierProvider(create: (_) => MemoryProvider()),
        ChangeNotifierProvider(create: (_) => MoodProvider()),
        // Consecutive days you showed up. Listens for the two things that
        // count rather than polling them, and reconciles a check-in that
        // happened before this provider existed (a cold start later the same
        // day) from the mood history.
        ChangeNotifierProxyProvider2<TaskProvider, MoodProvider,
            StreakProvider>(
          create: (_) => StreakProvider(),
          update: (_, tasks, mood, previous) {
            final streak = previous ?? StreakProvider();
            tasks.onTaskCompleted = streak.markToday;
            mood.onCheckIn = streak.markToday;
            if (mood.today != null) streak.markToday();
            return streak;
          },
        ),
        ChangeNotifierProvider(create: (_) => NotesProvider(ApiClient.instance)),
        // Goals depend on TaskProvider (they push today's milestones into it).
        ChangeNotifierProxyProvider<TaskProvider, GoalProvider>(
          create: (ctx) => GoalProvider(ctx.read<TaskProvider>()),
          update: (_, tasks, previous) => (previous ?? GoalProvider(tasks))..updateTasks(tasks),
        ),
        // Reminders hand themselves to the OS scheduler, and follow today's
        // timed blocks so a block you move takes its nudge with it.
        ChangeNotifierProxyProvider2<TaskProvider, GoalProvider,
            RemindersProvider>(
          create: (_) => RemindersProvider(),
          update: (_, tasks, goals, previous) => (previous ??
              RemindersProvider())
            ..updateTasks(tasks.daySchedule)
            ..updateGoals(goals.goals),
        ),
        // CoachProvider needs all 5 others - ProxyProvider wires them live.
        ChangeNotifierProxyProvider5<
            EnergyProvider,
            TaskProvider,
            HabitProvider,
            FocusProvider,
            SettingsProvider,
            CoachProvider>(
          create: (ctx) => CoachProvider(
            energy: ctx.read<EnergyProvider>(),
            tasks: ctx.read<TaskProvider>(),
            habits: ctx.read<HabitProvider>(),
            focus: ctx.read<FocusProvider>(),
            settings: ctx.read<SettingsProvider>(),
            // The signed-in account's name. The session is restored before
            // runApp, so this is populated by the time the coach is built; if
            // it is not, the coach stays nameless rather than inventing one.
            userName: ApiConfig.instance.displayName ?? '',
          ),
          update: (_, energy, tasks, habits, focus, settings, previous) {
            // Provider instances are long-lived; the ProxyProvider just
            // notifies on dependency changes. The coach reads state directly
            // from the providers it holds references to.
            return previous!;
          },
        ),
      ],
      // Rebuild MaterialApp when theme-affecting settings change.
      child: Consumer<SettingsProvider>(
        builder: (context, settings, _) {
          final hyperlegible = settings.hyperlegible;
          return MaterialApp(
            title: 'OurMynd',
            debugShowCheckedModeBanner: false,
            navigatorKey: rootNavigatorKey,
            scrollBehavior: const OmScrollBehavior(),
            themeMode: settings.themeMode,
            theme: AppTheme.light(hyperlegible: hyperlegible),
            darkTheme: AppTheme.dark(hyperlegible: hyperlegible),
            // The animated launch screen owns the first frame and hands over to
            // [initialRoute] once it has played. `home` rather than
            // `initialRoute` because the splash needs to be told where it is
            // going, and a named initial route has nowhere to carry that.
            home: SplashScreen(next: initialRoute, bootAt: bootAt),
            onGenerateRoute: AppRouter.onGenerateRoute,
            // Keep the Puter.js bridge alive app-wide, off-screen, above routes.
            //
            // The app content is Positioned.fill rather than a plain child: a
            // bare Stack hands its children loose constraints, so any route
            // that does not expand on its own collapses to the size of its
            // biggest widget and sits in the top-left corner. Every screen
            // with a ListView in it accidentally avoided that; the launch
            // screen, being a logo in the middle of nothing, did not. Pinning
            // it here fixes the class of bug rather than the one instance.
            // PuterHost stays unpositioned - it is a zero-size offscreen
            // webview and forcing it to fill would put it over the app.
            builder: (context, child) => Stack(
              children: [
                if (child != null) Positioned.fill(child: child),
                PuterHost(navigatorKey: rootNavigatorKey),
              ],
            ),
          );
        },
      ),
    );
  }
}
