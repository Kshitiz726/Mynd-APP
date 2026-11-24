// Smoke test: the app boots and renders without crashing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ourmynd/core/routes/app_routes.dart';
import 'package:ourmynd/main.dart';
import 'package:ourmynd/providers/settings_provider.dart';

void main() {
  testWidgets('OurMynd boots', (WidgetTester tester) async {
    await tester.pumpWidget(OurMyndApp(
      initialRoute: AppRoutes.login,
      // The launch screen measures its entrance from when main() started, so
      // it needs a start time to measure against.
      bootAt: DateTime.now(),
      // Loaded before runApp in the real app, so the first frame already
      // knows which theme to paint. Defaults are fine here.
      settings: SettingsProvider(),
    ));
    await tester.pump();

    // The app shell builds a MaterialApp at the root.
    expect(find.byType(MaterialApp), findsOneWidget);

    // Let the launch screen play out and hand over. Not pumpAndSettle: the orb
    // animates on a repeating controller and would never settle. These are
    // stepped past explicitly so no Timer outlives the test, which the binding
    // treats as a failure.
    // Each awaited delay only schedules the next one when it fires, so the
    // chain (hold, fade, route swap, the login screen's own entrance) needs a
    // pump per link rather than one long jump.
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  });
}
