import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/home/widgets/goal_sheet.dart';
import 'package:ourmynd/providers/energy_provider.dart';
import 'package:ourmynd/providers/goal_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// The new goal form, opened the way the nav bar opens it.
///
/// It threw "looking up a deactivated widget's ancestor is unsafe" on the first
/// keystroke, because the form reached back through the context of whoever
/// opened it for its themes, its pickers, its toasts and its pop - and the
/// thing that opened it was a sheet that closes itself on the way in. These pin
/// the two halves: the form must survive its opener disappearing, and the
/// pickers inside it must still open.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(void Function(BuildContext) onReady) => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => TaskProvider()),
          ChangeNotifierProvider(
            create: (c) => GoalProvider(c.read<TaskProvider>()),
          ),
          ChangeNotifierProvider(create: (_) => EnergyProvider()),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => onReady(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

  testWidgets('the form outlives the thing that opened it', (tester) async {
    late BuildContext shell;
    await tester.pumpWidget(host((c) => shell = c));

    // Opened from a sheet that pops itself the moment it is chosen, which is
    // exactly what the (+) in the nav bar does.
    await tester.tap(find.text('open'));
    await tester.pump();
    showModalBottomSheet<void>(
      context: shell,
      builder: (sheetContext) => TextButton(
        onPressed: () {
          Navigator.of(sheetContext).pop();
          showAddGoalSheet(shell);
        },
        child: const Text('new goal'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('new goal'));
    await tester.pumpAndSettle();

    expect(find.text('new goal'), findsWidgets);

    // The keystroke that used to bring the whole screen down.
    await tester.enterText(find.byType(TextField), 'run 5k');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('run 5k'), findsOneWidget);
  });

  testWidgets('the target date picker opens', (tester) async {
    late BuildContext shell;
    await tester.pumpWidget(host((c) => shell = c));
    await tester.tap(find.text('open'));
    await tester.pump();
    showAddGoalSheet(shell);
    await tester.pumpAndSettle();

    await tester.tap(find.text('pick a target date'));
    await tester.pumpAndSettle();

    // The picker's own help text, so this fails if the dialog never mounts
    // rather than only if it throws on the way up.
    expect(find.text('Achieve this goal by'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
