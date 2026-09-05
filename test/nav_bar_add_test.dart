import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/providers/nav_provider.dart';
import 'package:ourmynd/features/shell/widgets/om_nav_bar.dart';
import 'package:ourmynd/providers/settings_provider.dart';

/// The (+) in the middle of the nav bar.
///
/// It vanished on the coach tab, because the shell builds the bar from a
/// different branch there and that branch never passed `onAdd` - which the bar
/// treated as "draw nothing", leaving a hole in the middle on exactly one
/// screen. `onAdd` is required now, so the omission cannot compile; this pins
/// the other half: that the button is actually drawn, on whichever tab is
/// current.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // The bar's glass reads the low-stim setting, so it needs the provider even
  // though nothing here changes it.
  Widget host(AppTab current, {VoidCallback? onAdd}) => ChangeNotifierProvider(
        create: (_) => SettingsProvider(),
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            bottomNavigationBar: OmNavBar(
              current: current,
              onSelect: (_) {},
              onAdd: onAdd ?? () {},
            ),
          ),
        ),
      );

  testWidgets('the add button is on every tab, the coach included',
      (tester) async {
    for (final tab in AppTab.values) {
      await tester.pumpWidget(host(tab));
      await tester.pumpAndSettle();
      expect(
        find.bySemanticsLabel('add something'),
        findsOneWidget,
        reason: 'the (+) is missing on $tab',
      );
    }
  });

  testWidgets('tapping it opens whatever the shell passed', (tester) async {
    var taps = 0;
    await tester.pumpWidget(host(AppTab.coach, onAdd: () => taps++));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('add something'));
    await tester.pumpAndSettle();

    expect(taps, 1);
  });
}
