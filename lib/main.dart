import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/routes/app_router.dart';
import 'core/routes/app_routes.dart';
import 'core/services/account_scope.dart';
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
import 'providers/health_consent_provider.dart';
import 'providers/memory_provider.dart';
import 'providers/calendar_provider.dart';
import 'providers/motivation_provider.dart';
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

  // Silence debug logging in release builds.
  //
  // debugPrint keeps working in release - it is not compiled out - so the
  // verbose auth, sync and realtime tracing scattered through the app was
  // being written to the device log on real phones. None of it prints a token
  // or an email value, but it does narrate a user's session to anything that
  // can read the log, and on a health app that is more than we should say.
  // Assertions only run in debug, so this leaves development untouched.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Coach memory (parked thoughts + rolling summary) is app-wide; load it once
  // up front so parking a thought outside the coach screen merges, not clobbers.
  await _bootStep('coach memory', CoachMemoryService.instance.init);

  // The health-data consent answer, from this device's cache, before anything
  // can consult it. Nothing here gates on a network call: the provider fails
  // closed, so a launch that reached the first frame without this would spend
  // it treating a consenting user as if they had declined. The server is asked
  // straight after the session is restored, below.
  await _bootStep('health consent', HealthConsentProvider.instance.loadCached);

  // Auto-login: if a session was saved, restore it and reconnect realtime so we
  // land straight in the shell. Otherwise start at the login screen.
  //
  // A failure here is the one that costs the user something real - it drops
  // them at the login screen holding a session they never signed out of - so it
  // falls back to false explicitly rather than by accident.
  final hasSession =
      await _bootStep('session restore', SessionStore.restore) ?? false;
  // Demo mode has no session to authenticate the socket with, and an
  // unreachable server would just retry-storm in the background.
  if (hasSession && !kDemoMode) {
    await _bootStep('realtime', RealtimeService.instance.connect);
    // Reconcile with the server, which is where the evidence lives and which
    // knows about answers given on other devices and about a policy version
    // that has moved on since this one was cached. Deliberately not awaited:
    // the cached answer is already correct in the overwhelming majority of
    // launches, and holding the splash open for it would make every cold start
    // wait on a request whose answer it almost always already has.
    unawaited(HealthConsentProvider.instance.refresh());
  }

  await _bootStep('alarms', AlarmService.instance.init);
  // Channels and the timezone database, up front. The permission itself is
  // asked for on the first screen instead, where there is room to say why.
  await _bootStep('notifications', NotificationService.instance.init);

  // When the server stops accepting our token, go back to login instead of
  // sitting in a signed-in-looking app where every request fails. This is not
  // hypothetical: moving the backend from the laptop to the hosted server left
  // every device holding a token signed with the old secret, and the app kept
  // pretending it was logged in while nothing worked.
  ApiClient.onSessionExpired = () {
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    nav.pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  };

  // A different account just signed in on this device. Its own local data is
  // already in place and the previous account's is parked (see AccountScope);
  // this throws away everything still holding the previous user's data in
  // memory and starts the app over for the new one.
  //
  // Rebuilding from the root rather than resetting each provider by hand is
  // deliberate: there are a dozen of them, they load in their constructors, and
  // a reset method that someone forgets to add to provider thirteen brings the
  // whole bug back. Anything that survives this - notification channels, the
  // timezone database - is device state, not personal.
  AccountScope.onSwitched = () {
    // The socket is still authenticated as the previous user, and connect() is
    // a no-op while one exists. Drop it so the new session opens its own.
    RealtimeService.instance.dispose();
    // Consent belongs to an account, not to a phone. Forgetting it here is what
    // stops the incoming account inheriting the outgoing one's answer - which
    // would be wrong whichever way it pointed, but is worst when it silently
    // grants permission nobody on this account ever gave.
    unawaited(HealthConsentProvider.instance.clear());
    // The key is what makes this a restart rather than a repaint. runApp on an
    // app that is already running *updates* the root widget, and an updated
    // MultiProvider keeps every object it has already built - so the incoming
    // account carried on reading the outgoing one's tasks, goals and schedule
    // out of memory, which is the exact thing AccountScope exists to prevent.
    // A key the old root cannot match forces the whole tree to be built again
    // from the keys that were just swapped underneath it.
    runApp(OurMyndApp(
      key: ValueKey(AccountScope.generation),
      initialRoute: AppRoutes.shell,
      bootAt: DateTime.now(),
    ));
    // And then say where to go, because the new tree does not get a new
    // Navigator.
    //
    // rootNavigatorKey is a GlobalKey, so the Navigator from the outgoing tree
    // is reparented into the incoming one rather than rebuilt - and it brings
    // its route stack with it. At this moment that stack is the login screen
    // somebody has just signed in on. `home:` is never consulted, the splash
    // never runs, and the app sits on login looking like the sign-in silently
    // did nothing; only the second attempt worked, because by then the owner
    // key matched and none of this ran.
    //
    // Post-frame, so the swap has finished before the stack is rewritten.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      rootNavigatorKey.currentState
          ?.pushNamedAndRemoveUntil(AppRoutes.shell, (_) => false);
    });
  };

  runApp(OurMyndApp(
    initialRoute: (hasSession || kDemoMode) ? AppRoutes.shell : AppRoutes.login,
    bootAt: bootAt,
  ));
}

/// Run one piece of pre-`runApp` setup, and let the app start even if it fails.
///
/// The rule this enforces is that *nothing* before `runApp` may take the app
/// down. Awaiting a step bare meant any throw escaped `main()` before the first
/// frame, so no widget tree was ever built and the app sat on the Android
/// launch window with no error on screen and no way out. That is exactly what
/// happened on a release build: the resource shrinker had stripped the
/// notification icon (see android/app/src/main/res/raw/keep.xml), the plugin
/// threw `invalid_icon`, and a missing status-bar glyph presented as a dead
/// app.
///
/// Every step goes through here rather than only the ones that have failed so
/// far - a guard that covers the symptom you already found is not a guard. Each
/// keeps its own try/catch instead of one block around the whole sequence,
/// because a single catch would let an early failure skip every later step: a
/// bad coach-memory decode would silently cost the user their session.
///
/// Takes [FutureOr] so the synchronous steps are covered too - those throw on
/// `main()`'s own stack, which is the same dead launch window, not a lesser
/// case. Returns null on failure, so a step with a result can name its own
/// fallback at the call site.
///
/// The failure is still printed, so it stays diagnosable in `flutter run` and
/// `adb logcat` rather than being swallowed.
Future<T?> _bootStep<T>(String what, FutureOr<T> Function() run) async {
  try {
    return await run();
  } catch (e, st) {
    debugPrint('[boot] $what failed, continuing without it: $e\n$st');
    return null;
  }
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
        ChangeNotifierProvider(create: (_) => SettingsProvider()..loadRingtone()),
        // Subscription entitlement (Stripe). Gates premium-only features and
        // drives the paywall checkout. Refreshed after sign-in / on the paywall.
        ChangeNotifierProvider(create: (_) => PremiumProvider()..refresh()),
        ChangeNotifierProvider(create: (_) => NavProvider()),
        // A singleton behind a provider: the gate is consulted from plain
        // static code as well as from the widget tree, and both have to see
        // the same answer. See HealthConsentProvider.
        ChangeNotifierProvider<HealthConsentProvider>.value(
          value: HealthConsentProvider.instance,
        ),
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
        // Follows the tasks, so every edit, drag, tick and delete reaches the
        // calendar without each of those call sites having to remember.
        ChangeNotifierProxyProvider<TaskProvider, CalendarProvider>(
          create: (_) => CalendarProvider()..load(),
          update: (_, tasks, prev) => (prev ?? CalendarProvider()..load())..watch(tasks),
        ),
        // Bound to the mood and the memory rather than reading either at
        // generation time. The lines are written from what the app actually
        // knows about this person, and rewritten when that changes: a line
        // about somebody's week is only worth anything while it is still their
        // week.
        ChangeNotifierProxyProvider3<MoodProvider, MemoryProvider, TaskProvider,
            MotivationProvider>(
          create: (_) => MotivationProvider(),
          update: (_, mood, memory, tasks, prev) => (prev ?? MotivationProvider())
            ..bindMood(mood)
            ..bindMemory(memory)
            ..bindTasks(tasks),
        ),
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
          // Built at startup rather than on first read.
          //
          // Lazily, this provider only came into existence when something
          // looked at it - in practice, when the user opened the reminders
          // screen. Its constructor is what re-arms every pending reminder with
          // the OS, so until then nothing was re-scheduled: an app update, a
          // reboot, or the system dropping alarms left reminders silently dead
          // until you happened to visit that one screen. A reminder you set
          // last week has to survive without you ever opening the app again,
          // which means the re-arm cannot wait to be asked for.
          lazy: false,
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
            // Read once rather than proxied: MoodProvider is a single
            // long-lived instance, and the coach reads through the reference on
            // every turn, so there is nothing for a proxy to update.
            mood: ctx.read<MoodProvider>(),
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
