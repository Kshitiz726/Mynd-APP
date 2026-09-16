import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

/// When a second account signs in on the same device, AccountScope swaps the
/// local data underneath the app and main() calls runApp again to start over
/// for the new owner.
///
/// That only works if the new root is keyed. runApp on an app that is already
/// running *updates* the root widget rather than replacing it, and an updated
/// MultiProvider hands back every object it has already built - so the restart
/// meant to clear the previous account's tasks, goals and schedule out of
/// memory cleared nothing at all. Which is the exact bug AccountScope exists to
/// prevent, arriving by the route that was supposed to fix it.
///
/// The risk in keying it is the other way round: the app's root navigator has a
/// GlobalKey on it (ApiClient.onSessionExpired needs to reach it), and a
/// GlobalKey that appears twice in one frame is a hard framework error. So both
/// halves are pinned here - the providers really are rebuilt, and swapping the
/// root does not duplicate the key.
void main() {
  testWidgets('a keyed root restart rebuilds providers and keeps the navigator key',
      (tester) async {
    final navKey = GlobalKey<NavigatorState>();
    var builds = 0;

    Widget root(Key k) => KeyedSubtree(
          key: k,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<_Scoped>(
                // Eager, like RemindersProvider: the point is that the object
                // is made again, not that something happens to read it.
                lazy: false,
                create: (_) {
                  builds++;
                  return _Scoped();
                },
              ),
            ],
            child: MaterialApp(
              navigatorKey: navKey,
              home: const Scaffold(body: Text('signed in')),
            ),
          ),
        );

    await tester.pumpWidget(root(const ValueKey(0)));
    expect(builds, 1);
    expect(find.text('signed in'), findsOneWidget);

    // The switch: same widget type, new key.
    await tester.pumpWidget(root(const ValueKey(1)));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull,
        reason: 'the root navigator GlobalKey must survive the swap');
    expect(builds, 2,
        reason: 'the incoming account must not inherit the outgoing '
            "account's providers");
    expect(navKey.currentState, isNotNull);
    expect(find.text('signed in'), findsOneWidget);
  });

  testWidgets('an unkeyed rebuild keeps the previous providers', (tester) async {
    // The behaviour the key exists to avoid, pinned so nobody removes the key
    // believing runApp alone starts the app over.
    var builds = 0;
    Widget root() => MultiProvider(
          providers: [
            ChangeNotifierProvider<_Scoped>(
              lazy: false,
              create: (_) {
                builds++;
                return _Scoped();
              },
            ),
          ],
          child: const MaterialApp(home: Scaffold(body: Text('signed in'))),
        );

    await tester.pumpWidget(root());
    await tester.pumpWidget(root());
    await tester.pumpAndSettle();

    expect(builds, 1);
  });
}

class _Scoped extends ChangeNotifier {}
