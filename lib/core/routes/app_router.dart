import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../features/focus/focus_active_screen.dart';
import '../../features/notes/notes_screen.dart';
import '../../features/paywall/paywall_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/reminders/reminders_screen.dart';
import '../../features/coach/coach_screen.dart';
import '../../features/shell/app_shell.dart';
import '../../features/auth/login_screen.dart';
import '../../providers/settings_provider.dart';
import '../constants/app_durations.dart';
import 'app_routes.dart';

/// Central route generator for pushed (non-tab) screens. Page transitions use a
/// soft fade-through that collapses to an instant cut under reduce-motion.
abstract final class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final builder = switch (settings.name) {
      AppRoutes.shell => (_) => const AppShell(),
      AppRoutes.login => (_) => const LoginScreen(),
      AppRoutes.profile => (_) => const ProfileScreen(),
      AppRoutes.paywall => (_) => const PaywallScreen(),
      AppRoutes.notes => (_) => const NotesScreen(),
      AppRoutes.reminders => (_) => const RemindersScreen(),
      AppRoutes.focusActive => (_) => const FocusActiveScreen(),
      AppRoutes.focus => (_) => const FocusTabShell(),
      AppRoutes.coach => (_) => const CoachScreen(),
      _ => (_) => const AppShell(),
    };

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
