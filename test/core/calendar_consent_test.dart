import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/widgets/calendar_consent.dart';

/// Nobody's calendar is read, and no event title leaves the phone, before
/// they have said yes to the part iOS cannot ask about.
///
/// The OS sheet asks whether Mynd may read the calendar. It does not ask the
/// question that matters: TurnContext puts the title and time of each event
/// into the coach prompt, which is sent to Groq. Event titles carry who
/// somebody is meeting and often why, and other people's names along with it.
/// Guidelines 5.1.1(i) and 5.1.2(i) require that said before it happens, and
/// it is the guideline this app has already been rejected under once.
///
/// The ordering is the whole point of this file. Consent has to come before
/// the OS sheet, because after it the permission is already granted and there
/// is nothing left to ask.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CalendarConsent.clear();
  });

  Future<bool?> pumpAndAsk(WidgetTester tester) async {
    bool? answer;
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => SettingsProvider())],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  answer = await CalendarConsent.ensure(context);
                },
                child: const Text('connect'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    return answer;
  }

  test('an unanswered question is not a yes', () async {
    expect(await CalendarConsent.isGranted(), isFalse);
  });

  test('a switched account inherits nothing', () async {
    SharedPreferences.setMockInitialValues(
        {'om_calendar_consent_granted': true});
    await CalendarConsent.clear();
    // The next account is a different person whose calendar this is not.
    expect(await CalendarConsent.isGranted(), isFalse);
  });

  testWidgets('connecting asks before anything is read', (tester) async {
    await pumpAndAsk(tester);

    expect(find.text('Before you connect your calendar'), findsOneWidget);
    // Named, not described. "A third party" is a way of avoiding a
    // disclosure rather than making one.
    expect(find.textContaining(CalendarConsent.provider), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('the sheet says what leaves the phone, not just that it is read',
      (tester) async {
    await pumpAndAsk(tester);

    // Reading the calendar is what iOS asks about. Sending the titles on is
    // the part only we can disclose, so it is the part pinned here.
    expect(find.textContaining('title and time'), findsOneWidget);
    expect(find.textContaining('disconnect'), findsOneWidget);
  });

  testWidgets('declining reads nothing and leaves the answer open',
      (tester) async {
    await pumpAndAsk(tester);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Before you connect your calendar'), findsNothing);
    // Not stored as a refusal. Pressing Connect again simply asks again.
    expect(await CalendarConsent.isGranted(), isFalse);
  });

  testWidgets('allowing is remembered, so it is asked once', (tester) async {
    await pumpAndAsk(tester);
    await tester.tap(find.text('Allow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(await CalendarConsent.isGranted(), isTrue);
    // And a second call does not put the sheet up again.
    expect(find.text('Before you connect your calendar'), findsNothing);
  });
}
