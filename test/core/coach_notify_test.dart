import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/providers/coach_provider.dart';
import 'package:ourmynd/providers/energy_provider.dart';
import 'package:ourmynd/providers/focus_provider.dart';
import 'package:ourmynd/providers/habit_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// CoachScreen pushes the preferred name into CoachProvider from its `build`,
/// and the setter rewrites the welcome line when a name arrives, which notifies
/// listeners. Notifying while the tree is building throws
/// "setState() or markNeedsBuild() called during build".
///
/// It threw on every cold start with a name stored. The chat still rendered, so
/// it never looked broken - it was a red screen in the log and nothing more,
/// which is exactly the sort of thing that survives for months.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  CoachProvider makeCoach() => CoachProvider(
        energy: EnergyProvider(),
        tasks: TaskProvider(),
        habits: HabitProvider(),
        focus: FocusProvider(),
        settings: SettingsProvider(),
      );

  /// The provider seeds its welcome message from an async `_init`, and the
  /// setter only rewrites that message when it is the only one there. So the
  /// bug needs a settled provider to reproduce at all: called too early the
  /// list is still empty, the rewrite is skipped, and nothing notifies.
  Future<CoachProvider> settledCoach(WidgetTester tester) async {
    final coach = makeCoach();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pumpAndSettle();
    expect(coach.messages, hasLength(1),
        reason: 'the welcome message has to exist for this to be a real test');
    return coach;
  }

  testWidgets('setting the preferred name during build does not throw',
      (tester) async {
    final coach = await settledCoach(tester);

    // Reproduces the real call site, and it has to be reproduced in full. The
    // throw does not come from notifyListeners by itself: it comes from an
    // _InheritedProviderScope being marked dirty while the tree is building.
    // So the provider has to actually be in the tree with something watching
    // it, exactly as CoachScreen sits under the app's MultiProvider. Without
    // the Consumer below, this test passes against the broken code too.
    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider<CoachProvider>.value(
          value: coach,
          child: Consumer<CoachProvider>(
            builder: (context, watched, _) {
              watched.setPreferredName('Anj');
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull,
        reason: 'the notify has to wait for the end of the frame');

    // Deferred, not dropped.
    await tester.pumpAndSettle();
    expect(coach.messages.first.text, contains('Anj'),
        reason: 'the welcome line should have been rewritten for the name');
  });

  testWidgets('outside a build it still notifies immediately', (tester) async {
    final coach = await settledCoach(tester);

    var notified = 0;
    coach.addListener(() => notified++);

    // No build in progress here, so there is no reason to make anything wait.
    coach.setPreferredName('Anj');

    expect(notified, greaterThan(0),
        reason: 'deferring unconditionally would cost every caller a frame');
  });
}
