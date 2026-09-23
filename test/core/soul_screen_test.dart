import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/soul_service.dart';
import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/soul/soul_screen.dart';
import 'package:ourmynd/providers/settings_provider.dart';

/// The soul document steered every conversation while existing nowhere in the
/// interface, so "I don't see any SOUL.md" was a fair description of the app.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The back button is an OmTappable, which reads the low-stimulation setting.
  Widget host() => ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const SoulScreen(),
        ),
      );

  testWidgets('the screen names both halves of the document', (tester) async {
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.text('soul'), findsOneWidget);
    expect(find.text('SOUL.md'), findsOneWidget);
    expect(find.text('what it has picked up from you'), findsOneWidget);
  });

  testWidgets('it says plainly how it differs from memory', (tester) async {
    // The two are a pair and the difference is the whole point: one is what it
    // knows about you, the other is how it talks to you.
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.textContaining('Memory is what Mynd knows about you'),
        findsOneWidget);
  });

  testWidgets('with nothing learned yet it says so rather than showing blank',
      (tester) async {
    await SoulService.instance.init();
    await tester.pumpWidget(host());
    await tester.pump();

    expect(find.textContaining('watching how you write'), findsOneWidget);
  });
}
