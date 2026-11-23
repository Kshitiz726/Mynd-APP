import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/focus/focus_active_screen.dart';
import '../../features/notes/notes_screen.dart';
import '../../features/motivation/motivation_onboarding_screen.dart';
import '../../features/paywall/paywall_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/reminders/reminders_screen.dart';
import '../../features/coach/coach_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/shell/route_host.dart';
import '../../features/auth/login_screen.dart';
import '../../providers/settings_provider.dart';
import '../config/store_policy.dart';
import '../constants/app_durations.dart';
import 'app_routes.dart';

/// Central route generator for pushed (non-tab) screens. Page transitions use a
/// soft fade-through that collapses to an instant cut under reduce-motion.
abstract final class AppRouter {
  /// Which screen a route name resolves to.
  ///
  /// Split out from [onGenerateRoute] so a test can ask what a name builds
  /// without mounting it. That distinction matters here: the Route object is
  /// byte-identical whether or not the paywall is reachable - only the page it
  /// builds differs - so a test asserting on the Route passes for the wrong
  /// reason, and mounting the fallback needs the whole provider tree.
  /// Constructing a widget does neither.
  @visibleForTesting
  static WidgetBuilder builderFor(String? name) => switch (name) {
      AppRoutes.shell => (_) => const AppShell(),
      AppRoutes.login => (_) => const LoginScreen(),
      AppRoutes.profile => (_) => const ProfileScreen(),
      // The paywall exists only where the build may sell. On iOS this falls
      // through to the shell rather than rendering a screen whose only purpose
      // is to open an external payment page - so a deep link, a stale push or
      // a missed call site cannot reach it either. Hiding the buttons alone
      // would not do: what gets an app rejected under 3.1.1 is a reviewer
      // finding ANY route to that page.
      AppRoutes.paywall when StorePolicy.canSell => (_) => const PaywallScreen(),
      AppRoutes.motivation => (_) => const MotivationOnboardingScreen(),
      AppRoutes.notes => (_) => const NotesScreen(),
      AppRoutes.reminders => (_) => const RemindersScreen(),
      // Wrapped, like every other pushed screen: it paints no background of
      // its own, so bare it renders transparent over whatever is beneath.
      AppRoutes.focusActive => (_) => const RouteHost(child: FocusActiveScreen()),
      AppRoutes.focus => (_) => const RouteHost(child: FocusTabShell()),
      // showBack stays false because CoachScreen draws the back control itself,
      // inside its own header next to the avatar. `pushed: true` is what tells
      // it to: without it this route has no nav bar and no back button, which is
      // a dead end.
      AppRoutes.coach => (_) =>
          const RouteHost(showBack: false, child: CoachScreen(pushed: true)),
      _ => (_) => const AppShell(),
      };

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = builderFor(settings.name);

    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: AppDurations.pageTransition,
      pageBuilder: (context, _, __) => builder(context),
      transitionsBuilder: (context, animation, _, child) {
        final reduceMotion = context.read<SettingsProvider>().reduceMotion;
        if (reduceMotion) return child;
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        );
      },
    );
  }
}
