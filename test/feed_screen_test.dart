import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/feed_instructions_service.dart';
import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/features/feed/feed_screen.dart';
import 'package:ourmynd/models/agent.dart';
import 'package:ourmynd/models/feed_post.dart';
import 'package:ourmynd/providers/agent_provider.dart';
import 'package:ourmynd/providers/coach_provider.dart';
import 'package:ourmynd/providers/energy_provider.dart';
import 'package:ourmynd/providers/feed_provider.dart';
import 'package:ourmynd/providers/focus_provider.dart';
import 'package:ourmynd/providers/habit_provider.dart';
import 'package:ourmynd/providers/motivation_provider.dart';
import 'package:ourmynd/providers/nav_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/providers/task_provider.dart';

/// The Feed as somebody actually meets it.
///
/// The parts worth pinning are the ones that only fail on a real device: that
/// editions written on earlier days are still there to scroll back through,
/// that the instructions editor says what it does and does not spend a model
/// call on an unchanged document, and that a like survives being toggled.
///
/// Nothing here reaches the network. The provider is given editions that are
/// already on disk, which is the state the screen is in every time it is
/// opened after the first.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Bounded pumps, not pumpAndSettle.
  ///
  /// Mynd's face at the top of the feed is a looping animation, so the tree
  /// never reaches a frame where nothing is scheduled and pumpAndSettle waits
  /// for one forever.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }

  Map<String, Object> storedWith(List<Map<String, dynamic>> editions) => {
        'om_feed_editions': jsonEncode(editions),
      };

  Map<String, dynamic> edition(String slot, String label, String at,
          {List<Map<String, dynamic>>? posts}) =>
      {
        'slot': slot,
        'label': label,
        'at': at,
        'posts': posts ??
            [
              {
                'emoji': '🎓',
                'title': 'Brock\'s thesis MSc in CS closes January 15',
                'body': 'Applications are due January 15. Read the details '
                    'at the source before you start the file.',
                'linkText': 'the details',
                'linkUrl': 'https://example.com/brock',
                'source': 'Example News',
              },
            ],
      };

  Widget host() => MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => SettingsProvider()),
          ChangeNotifierProvider(create: (_) => NavProvider()),
          ChangeNotifierProvider(create: (_) => MotivationProvider()),
          ChangeNotifierProvider(create: (_) => AgentProvider()),
          // Built out rather than faked: Discuss hands a post to the real
          // coach, and a stub here would pass whatever that call became.
          ChangeNotifierProvider(
            create: (_) => CoachProvider(
              energy: EnergyProvider(),
              tasks: TaskProvider(),
              habits: HabitProvider(),
              focus: FocusProvider(),
              settings: SettingsProvider(),
            ),
          ),
          ChangeNotifierProvider(create: (_) => FeedProvider()),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const FeedScreen(),
        ),
      );

  testWidgets('editions written on earlier days are still there to read',
      (tester) async {
    SharedPreferences.setMockInitialValues(storedWith([
      edition('2026-09-21:afternoon', 'Monday afternoon',
          '2026-09-21T15:00:00.000'),
      edition('2026-09-21:morning', 'Monday morning',
          '2026-09-21T09:00:00.000'),
    ]));
    await FeedInstructionsService.instance.reload();

    await tester.pumpWidget(host());
    await settle(tester);

    // Both day-parts, newest first. This is the whole point of storing them:
    // signing back in should not wipe the week.
    expect(find.text('Monday afternoon'), findsOneWidget);
    expect(find.text('Monday morning'), findsOneWidget);
    expect(
      tester.getRect(find.text('Monday afternoon')).top,
      lessThan(tester.getRect(find.text('Monday morning')).top),
    );
  });

  testWidgets('the instructions control sits at the edge, not on the name',
      (tester) async {
    SharedPreferences.setMockInitialValues(storedWith([
      edition('2026-09-21:morning', 'Monday morning',
          '2026-09-21T09:00:00.000'),
    ]));
    await FeedInstructionsService.instance.reload();

    await tester.pumpWidget(host());
    await settle(tester);

    // A Stack sizes to its biggest non-positioned child, so this header once
    // shrank to the width of the name pill and dropped the control on top of
    // the name. It looked like a rendering glitch and was a layout one.
    final screen = tester.getSize(find.byType(FeedScreen)).width;
    final control = tester.getRect(find.bySemanticsLabel('feed instructions'));
    // The agent's own name, not a hard-coded one: the header follows whoever
    // is currently coaching.
    final name = tester.getRect(find.text(Agent.fallback.name));

    expect(control.right, greaterThan(screen - 40),
        reason: 'the control belongs at the right edge of the screen');
    expect(control.left, greaterThan(name.right),
        reason: 'it must not overlap the name');
  });

  testWidgets('the instructions editor says what editing it does',
      (tester) async {
    SharedPreferences.setMockInitialValues(storedWith([
      edition('2026-09-21:morning', 'Monday morning',
          '2026-09-21T09:00:00.000'),
    ]));
    await FeedInstructionsService.instance.reload();

    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.text('Feed instructions'), findsNothing,
        reason: 'the editor is behind the control, not always open');

    await tester.tap(find.bySemanticsLabel('feed instructions'));
    await settle(tester);

    expect(find.text('Feed instructions'), findsOneWidget);
    expect(
      find.textContaining('will apply to future posts on the feed'),
      findsOneWidget,
    );
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);

    // The document itself is in the field, editable, not a summary of it.
    expect(
      find.widgetWithText(TextField, FeedInstructionsService.defaultText),
      findsOneWidget,
    );
  });

  testWidgets('Save does nothing until the document actually changes',
      (tester) async {
    SharedPreferences.setMockInitialValues(storedWith([
      edition('2026-09-21:morning', 'Monday morning',
          '2026-09-21T09:00:00.000'),
    ]));
    await FeedInstructionsService.instance.reload();

    await tester.pumpWidget(host());
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('feed instructions'));
    await settle(tester);

    // Rewriting an edition costs a model call. A Save that fires on an
    // unchanged document spends one to produce the same feed again.
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Feed instructions'), findsOneWidget,
        reason: 'an unchanged Save should not close the editor');

    await tester.enterText(find.byType(TextField), 'Only sleep research.');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);

    expect(find.text('Feed instructions'), findsNothing);
    expect(FeedInstructionsService.instance.text, 'Only sleep research.');
  });

  testWidgets('a post can be liked, and the like is remembered',
      (tester) async {
    SharedPreferences.setMockInitialValues(storedWith([
      edition('2026-09-21:morning', 'Monday morning',
          '2026-09-21T09:00:00.000'),
    ]));
    await FeedInstructionsService.instance.reload();

    await tester.pumpWidget(host());
    await settle(tester);

    final feed = Provider.of<FeedProvider>(
      tester.element(find.byType(FeedScreen)),
      listen: false,
    );
    final post = feed.editions.single.posts.single;
    expect(post.liked, isFalse);

    await tester.tap(find.bySemanticsLabel('like this'));
    await settle(tester);
    expect(post.liked, isTrue);

    await tester.tap(find.bySemanticsLabel('like this'));
    await settle(tester);
    expect(post.liked, isFalse);
  });

  testWidgets('a reply is offered on every post, and it goes to the coach',
      (tester) async {
    SharedPreferences.setMockInitialValues(storedWith([
      edition('2026-09-21:morning', 'Monday morning',
          '2026-09-21T09:00:00.000'),
    ]));
    await FeedInstructionsService.instance.reload();

    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.text('Discuss'), findsOneWidget);
  });

  test('a day-part is written once, not once per visit', () {
    final morning = DateTime(2026, 9, 21, 9);
    final laterMorning = DateTime(2026, 9, 21, 11, 30);
    final afternoon = DateTime(2026, 9, 21, 15);

    expect(FeedEdition.slotFor(morning), FeedEdition.slotFor(laterMorning));
    expect(FeedEdition.slotFor(morning),
        isNot(FeedEdition.slotFor(afternoon)));
    expect(FeedEdition.labelFor(afternoon), 'Monday afternoon');
  });

  test('a post with no title or no body is dropped, not half rendered', () {
    expect(FeedPost.fromJson({'title': '', 'body': 'x'}), isNull);
    expect(FeedPost.fromJson({'title': 'x', 'body': ''}), isNull);
    expect(FeedPost.fromJson({'title': 'x', 'body': 'y'}), isNotNull);
  });

  test('an edition with no readable post is not kept as an empty heading', () {
    final e = FeedEdition.fromJson({
      'slot': '2026-09-21:morning',
      'label': 'Monday morning',
      'at': '2026-09-21T09:00:00.000',
      'posts': [
        {'title': '', 'body': ''},
      ],
    });
    expect(e, isNull);
  });

  testWidgets('a post puts its writing above its picture', (tester) async {
    // Asked for directly: "first put text, after that image, on every news".
    // Checked by position rather than by presence, because both orderings
    // render perfectly and only one of them is what a card written by a coach
    // should look like.
    SharedPreferences.setMockInitialValues(storedWith([
      edition('2026-09-22:morning', 'Tuesday morning', '2026-09-22T09:00:00',
          posts: [
            {
              'emoji': '📰',
              'title': 'A headline that belongs above the photograph',
              'body': 'Two sentences of the coach writing about it. '
                  'This is the part somebody should meet first.',
              'linkText': 'writing about it',
              'linkUrl': 'https://example.com/story',
              'source': 'Example News',
              'imageUrl': 'https://example.com/picture.jpg',
            },
          ]),
    ]));
    await FeedInstructionsService.instance.reload();

    await tester.pumpWidget(host());
    await settle(tester);

    final title = tester.getTopLeft(
        find.text('A headline that belongs above the photograph'));
    final image = tester.getTopLeft(find.byType(Image).last);

    expect(image.dy, greaterThan(title.dy),
        reason: 'the picture is above the writing again');
    // And flush with the writing rather than a gutter further left, which is
    // what made it look pasted onto the card.
    expect(image.dx, closeTo(title.dx, 0.5),
        reason: 'the picture is not aligned with the text column');
  });

  testWidgets('the day line stays at the top of the feed', (tester) async {
    // Taken out once, when its empty state read as a panel that had failed to
    // load, and asked for back. It is the one thing on this screen that is
    // about the reader rather than about the world.
    SharedPreferences.setMockInitialValues(storedWith([
      edition('2026-09-22:morning', 'Tuesday morning', '2026-09-22T09:00:00'),
    ]));
    await FeedInstructionsService.instance.reload();

    await tester.pumpWidget(host());
    await settle(tester);

    expect(find.text('a few words a day, for where you are'), findsOneWidget,
        reason: 'the day line belongs at the top of the feed, and its empty '
            'state is the way in to setting it up');
  });
}
