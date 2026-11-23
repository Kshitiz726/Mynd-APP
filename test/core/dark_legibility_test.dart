import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_colors.dart';
import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/home/widgets/week_strip.dart';
import 'package:ourmynd/providers/goal_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';
import 'package:ourmynd/widgets/om_button.dart';
import 'package:ourmynd/widgets/om_chip.dart';

/// Reads the colour the widget tree actually resolves, not the one the palette
/// could have supplied.
///
/// palette_contrast_test proves OmColors.onFill answers correctly. It cannot
/// prove a call site asked it. These three were the loudest places where the
/// site did not ask: in dark mode the selected day's number, the label on the
/// start button and a selected chip's label were all painted white on a light
/// fill, between 1.18:1 and 2.40:1, and every one of them looked to the user
/// like the control had stopped working rather than like a contrast bug.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget darkHost(Widget child) {
    final tasks = TaskProvider();
    return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: tasks),
          ChangeNotifierProvider(create: (_) => GoalProvider(tasks)),
          // OmButton and OmChip read the low-stimulation setting.
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: child),
        ));
  }

  /// WCAG relative contrast, on the two opaque colours a user sees.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  testWidgets('the selected day number is readable in dark mode',
      (tester) async {
    await tester.pumpWidget(darkHost(const WeekStrip()));
    await tester.pump();

    // The pill is filled with the brand indigo. It used to be filled with
    // c.text - near-white in dark - which made the number unreadable AND the
    // pill the brightest object on the screen; both are fixed by the fill,
    // not by the foreground.
    final today = DateTime.now().day.toString();
    final number = tester.widget<Text>(find.text(today).first);
    expect(number.style?.color, isNotNull);
    expect(contrast(number.style!.color!, OmColors.dark.brandSolid),
        greaterThanOrEqualTo(4.5),
        reason: 'the day you just tapped');
  });

  testWidgets('the accent button label is readable in dark mode',
      (tester) async {
    await tester.pumpWidget(
        darkHost(OmButton(label: 'start pomodoro', onPressed: () {})));
    await tester.pump();

    final label = tester.widget<Text>(find.text('start pomodoro'));
    expect(contrast(label.style!.color!, OmColors.dark.accent),
        greaterThanOrEqualTo(4.5),
        reason: 'the most-pressed button in the app');
  });

  testWidgets('a selected chip label is readable in dark mode',
      (tester) async {
    await tester.pumpWidget(darkHost(
        OmChip(label: 'low energy', selected: true, onTap: () {})));
    await tester.pump();

    final label = tester.widget<Text>(find.text('low energy'));
    final fill = tester
        .widget<AnimatedContainer>(find.byType(AnimatedContainer))
        .decoration as BoxDecoration;
    expect(contrast(label.style!.color!, fill.color!),
        greaterThanOrEqualTo(4.5),
        reason: 'a backlog filter you have picked');
  });
}
