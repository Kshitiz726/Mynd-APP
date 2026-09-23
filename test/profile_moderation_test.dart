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
    // Deletion lives one screen in, behind this row. Matched exactly, because
    // 'Account' on its own also matches the group heading above it - so the
    // old assertion passed on the heading alone and would have gone on passing
    // if the row itself disappeared.
    expect(find.text('Account and your data'), findsOneWidget);
  });

  testWidgets('no two rows lead to the same screen', (tester) async {
    // 'Account' and 'Your data' both opened AccountDataScreen, from two
    // different groups. Reading both and picking one is work that ends in the
    // same place either way, so one of them was pure cost.
    //
    // Tall enough for the whole page to lay out at once. The list is lazy, so
    // on the default surface the rows near the bottom are never built and
    // every findsNothing below would pass without proving anything.
    tester.view.physicalSize = const Size(393 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text('Your data'), findsNothing);

    // And the label matches what is behind it: this row opens the about page,
    // which is a version number and a licence list. The row that reaches a
    // person is 'Contact support', asserted above.
    expect(find.text('Help & Support'), findsNothing);
    expect(find.text('About OurMynd'), findsOneWidget);
  });

  testWidgets('Blocked accounts opens the unblock list', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    await tester.ensureVisible(find.text('Blocked accounts'));
    // The settings list grew, so this row now needs a real scroll to reach.
    // ensureVisible only *starts* it; without settling, the tap fires at the
    // coordinates the row had before the list moved.
    await tester.pumpAndSettle();
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
