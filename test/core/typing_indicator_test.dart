import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/coach/coach_screen.dart';
import 'package:ourmynd/providers/agent_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';

/// Mynd composing a reply.
///
/// Two places show this: the standalone row before a reply bubble exists,
/// and the bubble itself once it has opened but has no words yet. The second
/// was a literal '…' - a motionless full stop three times over - which is
/// what people actually saw, and is the thing being fixed.
///
/// The indicator used to be the word "thinking…" - a label, not a signal. It
/// never moved, so there was nothing on screen saying the app was still alive
/// while a slow reply arrived, which is the one moment that matters.
///
/// Two things are pinned here. That it actually animates, because a typing
/// indicator that does not is the bug being fixed. And that it stops dead
/// under reduce-motion, because this app is used by people for whom
/// involuntary movement in the corner of the eye is a cost, and an animation
/// that ignores that setting is worse than the static label was.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> pump(WidgetTester tester, {required bool reduceMotion}) async {
    final settings = SettingsProvider();
    settings.toggleReduceMotion(reduceMotion);
    final agents = AgentProvider();
    await agents.init();

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: settings),
        ChangeNotifierProvider.value(value: agents),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: CoachTypingIndicator())),
      ),
    ));
    await tester.pump();
  }

  /// Where the three dots are, vertically. Their offsets are the animation.
  List<double> dotTops(WidgetTester tester) => tester
      .widgetList<Transform>(find.descendant(
        of: find.byType(TypingDots),
        matching: find.byType(Transform),
      ))
      .map((t) => t.transform.getTranslation().y)
      .toList();

  testWidgets('there are three dots', (tester) async {
    await pump(tester, reduceMotion: false);
    expect(dotTops(tester).length, 3);
  });

  testWidgets('the dots move, and not all together', (tester) async {
    await pump(tester, reduceMotion: false);

    // Sampled across one period. A single pair of frames can land on two
    // points of equal height and look static when it is not.
    final seen = <String>{};
    var sawUneven = false;
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 90));
      final tops = dotTops(tester);
      seen.add(tops.map((d) => d.toStringAsFixed(2)).join(','));
      if (tops.toSet().length > 1) sawUneven = true;
    }

    expect(seen.length, greaterThan(3),
        reason: 'the dots never moved: this is the static label again');
    expect(sawUneven, isTrue,
        reason: 'all three dots move as one, which reads as a block sliding '
            'rather than as typing');
  });

  testWidgets('reduce motion stops it completely', (tester) async {
    await pump(tester, reduceMotion: true);

    final first = dotTops(tester);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    expect(dotTops(tester), first,
        reason: 'the dots are still moving with reduce-motion on');
    // Flat, not merely slow: every dot sits on the baseline.
    expect(first.every((d) => d == 0), isTrue);
  });

  testWidgets('it disposes without leaving a ticker behind', (tester) async {
    await pump(tester, reduceMotion: false);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    // A controller built lazily and first touched in dispose attaches its
    // ticker to a deactivated element and throws. Reaching here is the test.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dots are a plain row, usable inside a reply bubble',
      (tester) async {
    // The streaming bubble embeds TypingDots directly; anything that brought
    // its own bubble or padding would double up inside Mynd's.
    await pump(tester, reduceMotion: false);
    expect(find.byType(TypingDots), findsOneWidget);
  });
}
