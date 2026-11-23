import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/ai/ai_connections.dart';
import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/coach/coach_screen.dart';
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
import 'package:ourmynd/widgets/om_back_button.dart';

/// "Need help? Talk to Mynd" in Focus pushes the coach as its own route. On
/// that route there is no nav bar, because a pushed route sits over the shell,
/// and the header's drawer button does nothing, because OmPushDrawer only
/// exists inside the shell. The header drew that drawer button unconditionally,
/// so the screen had no exit of any kind - a dead end, and the sort of thing
/// App Review opens a rejection with.
///
/// The header decides from `pushed`, which is set by the caller rather than read
/// from the navigator: an earlier version keyed it on `Navigator.canPop()`,
/// which is a live reading of the stack, so pushing any sheet over the chat
/// flipped the hamburger into a back arrow mid-session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host({required bool pushed}) => MultiProvider(
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
          home: Scaffold(body: CoachScreen(pushed: pushed)),
        ),
      );

  testWidgets('the pushed coach route offers a way back', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(pushed: true));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(OmBackButton), findsOneWidget,
        reason: 'without this the route has no nav bar and no exit');
  });

  testWidgets('the chat tab keeps the drawer instead', (tester) async {
    tester.view.physicalSize = const Size(393 * 3, 2200 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(host(pushed: false));
    await tester.pump(const Duration(milliseconds: 400));

    // In the shell the nav bar is the way out, and the drawer is the only route
    // to side chats and Profile, so a back arrow here would take a control away
    // for one that does nothing.
    expect(find.byType(OmBackButton), findsNothing);
  });
}
