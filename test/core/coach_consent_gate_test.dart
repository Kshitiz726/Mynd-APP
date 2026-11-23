import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/ai/ai_connections.dart';
import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/coach/coach_screen.dart';
import 'package:ourmynd/features/onboarding/ai_consent_screen.dart';
import 'package:ourmynd/providers/agent_provider.dart';
import 'package:ourmynd/providers/ai_consent_provider.dart';
import 'package:ourmynd/providers/coach_provider.dart';
import 'package:ourmynd/providers/energy_provider.dart';
import 'package:ourmynd/providers/focus_provider.dart';
import 'package:ourmynd/providers/habit_provider.dart';
import 'package:ourmynd/providers/health_consent_provider.dart';
import 'package:ourmynd/providers/memory_provider.dart';
import 'package:ourmynd/providers/premium_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// Guideline 5.1.2(i): the app must ask before personal data reaches a
/// third-party AI provider. The coach is where that data moves, so the coach is
/// where the question has to be unavoidable.
///
/// This exists because the gate silently stopped working. It was written as
/// "ask once the server confirms nobody has answered", and with `/consent/ai`
/// returning 404 on both servers that condition was never true - so the
/// disclosure never appeared, and the chat opened and sent messages to the
/// provider with no consent on file. Nothing failed, nothing logged, and the
/// screen that exists to prevent the violation was simply never reached.
///
/// Asserted against the built widget tree, so it fails if the gate is removed
/// OR if it stops being reachable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  testWidgets('an unanswered user meets the disclosure, not the chat',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // No stored answer, and no reachable server - which is the state every
    // install is in today, because the endpoint is not deployed.
    SharedPreferences.setMockInitialValues({});
    await AiConsentProvider.instance.clear();
    await AiConsentProvider.instance.loadCached();

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AiConsentScreen), findsOneWidget,
        reason: 'nothing may be sent to the provider before this is answered');
  });

  testWidgets('somebody who already agreed goes straight to the chat',
      (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // The disclosure is asked once, not on every launch.
    SharedPreferences.setMockInitialValues({'om_ai_consent_granted': true});
    await AiConsentProvider.instance.loadCached();

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(AiConsentScreen), findsNothing);
  });

  testWidgets('changing your mind actually opens the coach', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Someone who said no, coming back to say yes. The coach shows them the
    // "it is off" screen, with a button onto the disclosure.
    SharedPreferences.setMockInitialValues({'om_ai_consent_granted': false});
    await AiConsentProvider.instance.loadCached();

    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.text('review and turn on the coach'));
    // Fixed pumps, not pumpAndSettle: the coach behind this route runs a
    // continuous animation, so there is no frame at which the tree is still.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(AiConsentScreen), findsOneWidget);

    // The screen that pushed this route is torn out before the answer lands.
    //
    // That is what happens on a device, and it is the whole bug. Recording
    // the answer notifies listeners, then awaits a write and a POST, and the
    // frames that run during those awaits rebuild the gate: `declined` is
    // false, _CoachNeedsAiConsent leaves the tree, and its context is dead by
    // the time onDecided is called. Staged explicitly here because a widget
    // test pumps no frames inside an await, so the race cannot be run - but
    // the state it produces can be, and the state is what breaks the pop.
    await AiConsentProvider.instance.grant(source: 'settings', company: 'Groq');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('agree, open the coach'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    // Popping through the pushing widget's context threw "looking up a
    // deactivated widget's ancestor", the route was never dismissed, and
    // pressing agree looked like it did nothing at all.
    expect(tester.takeException(), isNull,
        reason: 'the pop must not go through a dead context');
    expect(find.byType(AiConsentScreen), findsNothing,
        reason: 'agreeing has to leave the disclosure');
    expect(AiConsentProvider.instance.granted, isTrue);
  });
}
