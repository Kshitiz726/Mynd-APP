import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/api_config.dart';
import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/focus/focus_screen.dart';
import 'package:ourmynd/models/energy_level.dart';
import 'package:ourmynd/models/task.dart';
import 'package:ourmynd/providers/focus_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// The focus screen's promise is "the block you are already in, one tap away,
/// for exactly the time it has left". That arithmetic is pinned here, along
/// with the screen actually rendering.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ApiConfig.instance.displayName = 'Kshitiz';
  });

  Widget host(TaskProvider tasks, FocusProvider focus) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: tasks),
          ChangeNotifierProvider.value(value: focus),
          // OmButton reads the low-stimulation setting.
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: FocusScreen()),
        ),
      );

  /// A block that started 40 minutes ago and runs for two hours.
  Task inProgress() {
    final now = DateTime.now();
    return Task(
      id: 'deep',
      title: 'Write the thesis intro',
      time: 'now',
      energy: EnergyLevel.high,
      scheduled: true,
      startTime: now.subtract(const Duration(minutes: 40)),
      duration: const Duration(hours: 2),
    );
  }

  testWidgets('greets the user by name and surfaces the block on the clock',
      (tester) async {
    final tasks = TaskProvider()..addTasks([inProgress()]);
    await tester.pumpWidget(host(tasks, FocusProvider()));
    await tester.pump();

    expect(find.text('Kshitiz'), findsOneWidget);
    expect(find.text('HAPPENING NOW'), findsOneWidget);
    expect(find.text('Write the thesis intro'), findsOneWidget);
    expect(find.text('focus on this task'), findsOneWidget);
  });

  testWidgets('focusing on a task runs its remaining time, not its full length',
      (tester) async {
    final tasks = TaskProvider()..addTasks([inProgress()]);
    final focus = FocusProvider();
    await tester.pumpWidget(host(tasks, focus));
    await tester.pump();

    await tester.tap(find.text('focus on this task'));
    await tester.pump();

    expect(focus.isActive, isTrue);
    expect(focus.activeTaskTitle, 'Write the thesis intro');
    // 2h block entered 40 minutes late leaves 1h20m, give or take the second
    // the test itself takes to run.
    expect(focus.secondsRemaining, closeTo(80 * 60, 5));
    // And the ring measures against that same length, not the mode's.
    expect(focus.totalSeconds, focus.secondsRemaining);
    expect(focus.timeString.startsWith('1:19') || focus.timeString.startsWith('1:20'), isTrue,
        reason: 'long sessions read as h:mm:ss, got ${focus.timeString}');

    focus.end();
  });

  testWidgets('a saved focus persists and starts at its own length', (tester) async {
    final tasks = TaskProvider();
    final focus = FocusProvider();
    focus.addSavedFocus(name: 'Read Atomic Habits', minutes: 30);

    await tester.pumpWidget(host(tasks, focus));
    await tester.pump();

    expect(find.text('Read Atomic Habits'), findsOneWidget);
    expect(find.text('new focus'), findsOneWidget);

    await tester.tap(find.text('Read Atomic Habits'));
    await tester.pump();

    expect(focus.activeTaskTitle, 'Read Atomic Habits');
    expect(focus.secondsRemaining, 30 * 60);

    focus.end();
  });
}
