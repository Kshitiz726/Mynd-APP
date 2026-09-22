import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/widgets/om_push_drawer.dart';

/// The side panel that pushes the app aside instead of covering it.
///
/// Worth pinning because the failure modes are all invisible in a screenshot:
/// a panel that is tappable while it is hidden underneath the app, an app that
/// still takes taps while it is parked off to the side, and a panel that
/// cannot be closed. Each one leaves a build that looks right and is unusable.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host() => MaterialApp(
        theme: AppTheme.light(),
        home: OmPushDrawer(
          panel: Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () {},
                child: const Text('panel item'),
              ),
            ),
          ),
          child: const Scaffold(body: Center(child: Text('the app'))),
        ),
      );

  /// Where the app's content actually sits on screen.
  double appLeftEdge(WidgetTester tester) =>
      tester.getRect(find.text('the app')).left;

  testWidgets('closed, the app is in place and the panel takes no taps',
      (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    final closed = appLeftEdge(tester);

    // The panel is built and painted underneath from the first frame - that is
    // what makes the open cheap - so "hidden" has to mean it ignores pointers,
    // not that it is absent.
    expect(find.text('panel item'), findsOneWidget);
    expect(find.text('the app'), findsOneWidget);

    final state = tester.state<OmPushDrawerState>(find.byType(OmPushDrawer));
    expect(state.isOpen, isFalse);
    expect(closed, lessThan(tester.getSize(find.byType(OmPushDrawer)).width / 2),
        reason: 'the app should start un-pushed');
  });

  testWidgets('opening slides the app to the right', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final closed = appLeftEdge(tester);

    tester.state<OmPushDrawerState>(find.byType(OmPushDrawer)).open();
    await tester.pumpAndSettle();

    expect(appLeftEdge(tester), greaterThan(closed + 100),
        reason: 'the app, and with it the nav bar, moves aside');
    expect(
        tester.state<OmPushDrawerState>(find.byType(OmPushDrawer)).isOpen,
        isTrue);
  });

  testWidgets('tapping the parked app closes it again', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    final closed = appLeftEdge(tester);

    final state = tester.state<OmPushDrawerState>(find.byType(OmPushDrawer));
    state.open();
    await tester.pumpAndSettle();

    // Anywhere on the parked app, not a dedicated close button: this is the
    // only way back for somebody who opened it by accident. The app is pushed
    // most of the way off the right, so this is the sliver still showing.
    await tester.tapAt(const Offset(760, 300));
    await tester.pumpAndSettle();

    expect(state.isOpen, isFalse);
    expect(appLeftEdge(tester), closeTo(closed, 0.5));
  });

  testWidgets('a drag from the left edge opens it', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.timedDragFrom(
      const Offset(6, 400),
      const Offset(260, 0),
      const Duration(milliseconds: 220),
    );
    await tester.pumpAndSettle();

    expect(
        tester.state<OmPushDrawerState>(find.byType(OmPushDrawer)).isOpen,
        isTrue);
  });

  testWidgets('with dragEnabled false the edge drag does nothing',
      (tester) async {
    // The other tabs. A horizontal swipe there belongs to the week rail or a
    // carousel, and the chat's index has no business stealing it.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: const OmPushDrawer(
        dragEnabled: false,
        panel: Scaffold(body: Center(child: Text('panel item'))),
        child: Scaffold(body: Center(child: Text('the app'))),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.timedDragFrom(
      const Offset(6, 400),
      const Offset(260, 0),
      const Duration(milliseconds: 220),
    );
    await tester.pumpAndSettle();

    expect(
        tester.state<OmPushDrawerState>(find.byType(OmPushDrawer)).isOpen,
        isFalse);
  });
}
