import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/providers/settings_provider.dart';
import 'package:ourmynd/widgets/om_mic_button.dart';

/// Voice in the composer is only worth having if the words land where you were
/// already writing. These pin the joining rules, which are the whole
/// difference between dictation and a field that gets clobbered.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // Consent already given, so these exercise the recording path rather
    // than the disclosure in front of it. The sheet itself, and the fact it
    // is there at all, are pinned in voice_consent_test.dart - this file is
    // about what the button does once the microphone is allowed to open.
    SharedPreferences.setMockInitialValues({'om_voice_consent_granted': true});
  });

  group('insertDictation', () {
    test('an empty field just takes the words', () {
      final out = insertDictation(const TextEditingValue(), 'buy milk');
      expect(out.text, 'buy milk');
      expect(out.selection.baseOffset, 'buy milk'.length);
    });

    test('a field that was never focused appends rather than prepending', () {
      // An untouched TextField reports selection offset -1. Read as an offset
      // that puts the words at the start of the sentence, which is the one
      // place they do not belong.
      final out = insertDictation(
        const TextEditingValue(
          text: 'remind me to',
          selection: TextSelection.collapsed(offset: -1),
        ),
        'call the dentist',
      );
      expect(out.text, 'remind me to call the dentist');
    });

    test('inserting mid-sentence spaces both sides', () {
      final out = insertDictation(
        const TextEditingValue(
          text: 'buy milk and eggs',
          selection: TextSelection.collapsed(offset: 8), // after "buy milk"
        ),
        'today',
      );
      expect(out.text, 'buy milk today and eggs');
    });

    test('it does not double a space that is already there', () {
      final out = insertDictation(
        const TextEditingValue(
          text: 'buy milk ',
          selection: TextSelection.collapsed(offset: 9),
        ),
        'and eggs',
      );
      expect(out.text, 'buy milk and eggs');
    });

    test('a selection is replaced, not nudged aside', () {
      final out = insertDictation(
        const TextEditingValue(
          text: 'buy milk',
          selection: TextSelection(baseOffset: 4, extentOffset: 8),
        ),
        'bread',
      );
      expect(out.text, 'buy bread');
    });

    test('the caret ends after the words, ready for the next ones', () {
      final out = insertDictation(
        const TextEditingValue(
          text: 'a b',
          selection: TextSelection.collapsed(offset: 1), // between "a" and " b"
        ),
        'x',
      );
      expect(out.text, 'a x b');
      expect(out.text.substring(0, out.selection.baseOffset), 'a x');
    });

    test('nothing said, nothing changed', () {
      const before = TextEditingValue(
        text: 'half a thought',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(insertDictation(before, '   ').text, before.text);
      expect(insertDictation(before, '').selection, before.selection);
    });

    test('a stale selection past the end of the text cannot crash it', () {
      // Possible when the controller's text is replaced without its selection
      // being brought along. substring would throw on the raw offsets.
      final out = insertDictation(
        const TextEditingValue(
          text: 'hi',
          selection: TextSelection(baseOffset: 40, extentOffset: 90),
        ),
        'there',
      );
      expect(out.text, 'hi there');
    });
  });

  group('OmMicButton', () {
    // OmTappable reads the reduce-motion setting, so the button cannot be
    // mounted bare.
    Widget host(TextEditingController controller,
            {ValueChanged<String>? onError, bool enabled = true}) =>
        ChangeNotifierProvider(
          create: (_) => SettingsProvider(),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(
              body: Center(
                child: OmMicButton(
                  controller: controller,
                  onError: onError,
                  enabled: enabled,
                ),
              ),
            ),
          ),
        );

    String labelOf(WidgetTester tester) =>
        tester.getSemantics(find.byType(OmMicButton)).label;

    testWidgets('at rest it offers to dictate, and can be tapped',
        (tester) async {
      await tester.pumpWidget(host(TextEditingController()));
      expect(
        tester.getSemantics(find.byType(OmMicButton)),
        matchesSemantics(
          label: 'dictate',
          isButton: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('it does not claim to be listening until the mic is open',
        (tester) async {
      // The whole point of the opening state. There is no permission channel
      // on a test host, so the call to open the mic stays pending - exactly as
      // it does on a real phone for as long as the OS dialog is up. Through
      // that window the button must not show the listening fill, because
      // nothing is being recorded and anything said into it is lost.
      String? said;
      await tester.pumpWidget(
          host(TextEditingController(), onError: (m) => said = m));

      await tester.tap(find.byType(OmMicButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));

      expect(labelOf(tester), 'opening the microphone, tap to cancel');
      expect(said, isNull, reason: 'nothing has failed yet');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a second tap abandons a mic that never opened',
        (tester) async {
      // Otherwise an unanswered permission dialog pins the button in a state
      // it has no way out of.
      final controller = TextEditingController(text: 'half a thought');
      await tester.pumpWidget(host(controller));

      await tester.tap(find.byType(OmMicButton));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(OmMicButton));
      await tester.pump(const Duration(milliseconds: 300));

      expect(labelOf(tester), 'dictate');
      expect(controller.text, 'half a thought',
          reason: 'an abandoned dictation must not touch what was typed');
      expect(tester.takeException(), isNull);
    });

    testWidgets('tearing it down mid-attempt does not throw', (tester) async {
      // The ticker used to be a `late final` initialiser, so for a composer
      // that was never dictated into the first touch of it was dispose - where
      // attaching a ticker looks up an inherited widget on an element that has
      // already been deactivated, and asserts.
      await tester.pumpWidget(host(TextEditingController()));
      await tester.tap(find.byType(OmMicButton));
      await tester.pump(const Duration(milliseconds: 200));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('an unused mic can be torn down too', (tester) async {
      await tester.pumpWidget(host(TextEditingController()));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });

    testWidgets('disabled it cannot be started', (tester) async {
      String? said;
      await tester.pumpWidget(host(TextEditingController(),
          onError: (m) => said = m, enabled: false));
      await tester.tap(find.byType(OmMicButton), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400));
      expect(said, isNull);
      expect(labelOf(tester), 'dictate');
    });
  });
}
