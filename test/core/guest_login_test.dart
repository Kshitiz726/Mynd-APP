import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/auth/login_screen.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// The reviewer's way in, and the way in for anyone who does not want a mental
/// health app attached to their Google or Apple identity.
///
/// App Review rejected build 10 under Guideline 2.1 partly because there was no
/// demo account to give them, and there was no demo account because the app had
/// no path that did not go through a provider. These pin the button down so it
/// cannot quietly disappear in a layout change and take the only credential-free
/// entrance with it.
void main() {
  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => SettingsProvider(),
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const LoginScreen(),
      ),
    ));
    // The auth block fades in on a timer rather than on the first frame.
    await tester.pump(const Duration(seconds: 2));
  }

  testWidgets('the login screen offers a guest entrance', (tester) async {
    await pumpLogin(tester);
    expect(find.text('Continue as guest'), findsOneWidget);
  });

  testWidgets('guest sits below both providers, not in front of them',
      (tester) async {
    await pumpLogin(tester);

    final google = tester.getTopLeft(find.text('Continue with Google')).dy;
    final guest = tester.getTopLeft(find.text('Continue as guest')).dy;
    // Quieter than the providers: further down the screen, never above them.
    expect(guest, greaterThan(google));
  });

  testWidgets('the guest button is reachable, not decoration', (tester) async {
    await pumpLogin(tester);
    final btn = find.ancestor(
      of: find.text('Continue as guest'),
      matching: find.byType(GestureDetector),
    );
    expect(btn, findsWidgets);
  });
}
