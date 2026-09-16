import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/community/user_profile_sheet.dart';
import 'package:ourmynd/features/profile/blocked_accounts_screen.dart';
import 'package:ourmynd/features/profile/profile_screen.dart';
import 'package:ourmynd/providers/health_consent_provider.dart';
import 'package:ourmynd/providers/nav_provider.dart';
import 'package:ourmynd/providers/premium_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';

/// Guideline 1.2 asks for three things in an app carrying user-generated
/// content: a way to report, a way to block, and a way to reach a human. The
/// first lives on the community surfaces; the other two live here, and they are
/// only worth anything if somebody can actually get to them.
///
/// This exists because the question "is blocking really in the build?" was
/// asked, and reading the source back is not an answer. It also guards a
/// mistake this file has made before: the Account row once pointed at the
/// paywall, which left account deletion with no caller anywhere in the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => PremiumProvider()),
          ChangeNotifierProvider(create: (_) => NavProvider()),
          ChangeNotifierProvider.value(value: HealthConsentProvider.instance),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const ProfileScreen(),
        ),
      );

  testWidgets('profile carries the Guideline 1.2 rows', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text('Blocked accounts'), findsOneWidget);
    expect(find.text('Contact support'), findsOneWidget);
    // Deletion lives one screen in, behind this row.
    expect(find.text('Account'), findsWidgets);
  });

  testWidgets('Blocked accounts opens the unblock list', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.ensureVisible(find.text('Blocked accounts'));
    await tester.tap(find.text('Blocked accounts'));
    await tester.pumpAndSettle();

    expect(find.byType(BlockedAccountsScreen), findsOneWidget);
  });

  /// The profile sheet is the one screen that is only ever about another
  /// person, which makes it the place somebody goes to get rid of them. It
  /// carries report and block for every caller - a group chat member, and the
  /// stranger matchmaking has just paired you with - so none of those surfaces
  /// has to remember to wire it up. A build where this row is missing is a
  /// build where the only route to blocking is a long-press nobody discovers.
  testWidgets('a person profile offers report and block', (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        // OmTappable reads the reduced-motion and haptics settings.
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => UserProfileSheet.show(context, 'someone-else',
                fallbackName: 'Sam'),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    // The sheet fetches the profile and there is no server here, so it settles
    // on the fallback name. That is the worst case and the one worth pinning:
    // the action has to be there even when the profile could not be loaded.
    await tester.pumpAndSettle();

    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('Report or block'), findsOneWidget);
  });
}
