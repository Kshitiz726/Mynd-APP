import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/home/widgets/motivation_card.dart';
import 'package:ourmynd/models/motivation.dart';
import 'package:ourmynd/providers/motivation_provider.dart';
import 'package:ourmynd/providers/mood_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/widgets/shimmer_swipe.dart';

/// The loading state was reported as missing, and it was: the flag driving it
/// was only set inside the write itself, behind gates that returned before it
/// and for less time than a frame when the local bank answered. These pin the
/// two halves of the fix at the level somebody actually sees it - the card.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  Widget host(MotivationProvider motivation, MoodProvider mood) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: motivation),
          ChangeNotifierProvider.value(value: mood),
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: MotivationCard()),
        ),
      );

  Future<MotivationProvider> onboarded() async {
    final m = MotivationProvider();
    await m.load();
    await m.save(const MotivationSettings(onboarded: true));
    return m;
  }

  testWidgets('an onboarded card shows a shimmering skeleton while it writes',
      (tester) async {
    // The card asks for its first batch on mount, so this is the loading state
    // reached the way somebody actually reaches it. Asserting the swap back to
    // words would mean driving a write to completion, and the mocked HTTP in
    // testWidgets needs runAsync rather than the fake clock to get there - the
    // provider tests cover that half, where it can be done honestly.
    final motivation = await onboarded();
    final mood = MoodProvider();
    motivation.bindMood(mood);

    await tester.pumpWidget(host(motivation, mood));

    expect(find.byType(ShimmerSwipe), findsOneWidget);
    // The skeleton, not the real card wearing a sheen: no line is showing.
    expect(find.textContaining('a few words a day'), findsNothing);

    motivation.dispose();
    await tester.pump();
  });

  testWidgets('a card that is not set up never shows the skeleton',
      (tester) async {
    // The gate is deliberate: with the feature switched off nothing is being
    // written, so a loading state would be a promise of words that are not
    // coming.
    final motivation = MotivationProvider();
    await motivation.load();
    final mood = MoodProvider();
    motivation.bindMood(mood);

    await tester.pumpWidget(host(motivation, mood));
    await mood.checkIn(Mood.rough);
    await tester.pump();

    expect(find.byType(ShimmerSwipe), findsNothing);
    expect(find.text('a few words a day, for where you are'), findsOneWidget);
    motivation.dispose();
  });
}
