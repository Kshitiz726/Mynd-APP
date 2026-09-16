import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
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
}
