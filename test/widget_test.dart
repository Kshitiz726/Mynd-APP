// Smoke test: the app boots and renders without crashing.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ourmynd/core/routes/app_routes.dart';
import 'package:ourmynd/main.dart';

void main() {
  testWidgets('OurMynd boots', (WidgetTester tester) async {
    await tester.pumpWidget(const OurMyndApp(initialRoute: AppRoutes.login));
    await tester.pump();

    // The app shell builds a MaterialApp at the root.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
