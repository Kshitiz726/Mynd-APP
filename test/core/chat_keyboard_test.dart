import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/coach/coach_screen.dart';
import 'package:ourmynd/providers/agent_provider.dart';
import 'package:ourmynd/providers/coach_provider.dart';
import 'package:ourmynd/providers/energy_provider.dart';
import 'package:ourmynd/providers/focus_provider.dart';
import 'package:ourmynd/providers/habit_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';
import 'package:ourmynd/providers/health_consent_provider.dart';
import 'package:ourmynd/providers/ai_consent_provider.dart';
import 'package:ourmynd/core/services/ai/ai_connections.dart';
import 'package:ourmynd/providers/memory_provider.dart';
import 'package:ourmynd/providers/premium_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';

/// The keyboard stayed up over the conversation and tapping anything else did
/// not put it away. Flutter only dismisses on a tap outside on desktop; on a
/// phone the field keeps focus until something takes it, and nothing did.
///
/// Asserted against the built widget tree rather than the source text, so this
/// fails if the properties are removed OR if the composer stops being reached.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => AgentProvider()),
          ChangeNotifierProvider(
            create: (_) => CoachProvider(
              energy: EnergyProvider(),
              tasks: TaskProvider(),
              habits: HabitProvider(),
              focus: FocusProvider(),
              settings: SettingsProvider(),
            ),
          ),
          ChangeNotifierProvider(create: (_) => MemoryProvider()),
          ChangeNotifierProvider(create: (_) => PremiumProvider()),
          ChangeNotifierProvider.value(value: HealthConsentProvider.instance),
          ChangeNotifierProvider.value(value: AiConsentProvider.instance),
          ChangeNotifierProvider.value(value: AiConnections.instance),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: CoachScreen()),
        ),
      );

  testWidgets('the composer gives the keyboard up on a tap outside',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    expect(fields, isNotEmpty, reason: 'the composer was not built at all');
    expect(
      fields.any((f) => f.onTapOutside != null),
      isTrue,
      reason: 'nothing takes focus back when you tap elsewhere, so the '
          'keyboard sits over the conversation',
    );
  });

  testWidgets('dragging the conversation dismisses the keyboard',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    final lists = tester.widgetList<ListView>(find.byType(ListView));
    expect(lists, isNotEmpty);
    expect(
      lists.any((l) =>
          l.keyboardDismissBehavior == ScrollViewKeyboardDismissBehavior.onDrag),
      isTrue,
      reason: 'scrolling is the first thing people try when the keyboard is '
          'covering what they want to read',
    );
  });

  testWidgets('the empty state lays out on a phone without overflowing',
      (tester) async {
    // Found by the two tests above rather than by looking: this screen
    // overflowed by 233 pixels because the agent pill put a whole tagline in
    // an unbounded Row. It is the first screen a new account sees.
    tester.view.physicalSize = const Size(393 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull,
        reason: 'the chat empty state painted overflow stripes');
  });
}
