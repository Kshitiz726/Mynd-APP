import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/widgets/om_mic_button.dart';
import 'package:ourmynd/widgets/voice_consent.dart';

/// Nobody's voice leaves the phone before they have said yes.
///
/// Dictation is not done on the device: the recording is uploaded to Groq,
/// transcribed and sent back. Guidelines 5.1.1(i) and 5.1.2(i) require that
/// to be disclosed before it happens, and it is the guideline this app has
/// already been rejected under once.
///
/// The gate lives on the button rather than on the screens that host one.
/// That is the whole point of this file: the brain dump's microphone had no
/// gate at all, and the chat's was covered only because the chat sits behind
/// the consent screen. A rule enforced per host is a rule that is missing
/// from whichever host is added next.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await VoiceConsent.clear();
  });

  Future<void> pumpMic(WidgetTester tester, TextEditingController c) async {
    await tester.pumpWidget(MultiProvider(
      providers: [ChangeNotifierProvider(create: (_) => SettingsProvider())],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(body: Center(child: OmMicButton(controller: c))),
      ),
    ));
    await tester.pump();
  }

  test('an unanswered question is not a yes', () async {
    expect(await VoiceConsent.isGranted(), isFalse);
  });

  test('a switched account inherits nothing', () async {
    SharedPreferences.setMockInitialValues({'om_voice_consent_granted': true});
    await VoiceConsent.clear();
    // The next account is a different person and has agreed to nothing. An
    // answer that carried over would be consent given by somebody else.
    expect(await VoiceConsent.isGranted(), isFalse);
  });

  testWidgets('pressing the mic asks before anything is recorded',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpMic(tester, controller);

    await tester.tap(find.byType(OmMicButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Before you use the microphone'), findsOneWidget);
    // Named, not described. "A third party" is a way of avoiding a
    // disclosure rather than making one.
    expect(find.textContaining(VoiceConsent.provider), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
    expect(find.text('Not now'), findsOneWidget);
  });

  testWidgets('declining records nothing and leaves the answer open',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpMic(tester, controller);

    await tester.tap(find.byType(OmMicButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Not now'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Before you use the microphone'), findsNothing);
    // Not stored as a refusal. Somebody who tapped the mic by accident
    // should not have to go hunting through settings to undo it - pressing
    // it again simply asks again.
    expect(await VoiceConsent.isGranted(), isFalse);
  });

  testWidgets('the sheet names what is kept as well as what is sent',
      (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await pumpMic(tester, controller);

    await tester.tap(find.byType(OmMicButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The part people do not expect: a microphone picks up the room, not
    // only the person holding it.
    expect(find.textContaining('other people nearby'), findsOneWidget);
    expect(find.textContaining('withdraw'), findsOneWidget);
  });
}
