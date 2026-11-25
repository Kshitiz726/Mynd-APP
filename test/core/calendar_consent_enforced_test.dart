import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/calendar_service.dart';
import 'package:ourmynd/widgets/calendar_consent.dart';

/// Consent is enforced where the data moves, not only where the button is.
///
/// The sheet in CalendarConsent is shown by CalendarConnectCard, and today
/// that is the only place calendar access is asked for. That was the whole
/// control, and it had two gaps:
///
///   1. A caller added later could simply not show the sheet. A comment asking
///      the next person to remember is not a control.
///
///   2. An install that connected a calendar on an older build - one that
///      asked iOS for permission but never asked about sending titles onward -
///      carries `connected == true` across the update. The sheet never runs
///      again, so the titles kept flowing on a yes nobody gave.
///
/// Both are closed by checking the consent at the two points that matter: the
/// moment the OS sheet would be raised, and the moment titles would be put
/// into a prompt. Both fail closed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await CalendarConsent.clear();
  });

  test('the OS sheet is not raised before the disclosure is agreed to',
      () async {
    expect(await CalendarConsent.isGranted(), isFalse);

    // No plugin call is reached, so this returns false without ever touching
    // the platform channel. That is the point: on a phone it means iOS is
    // never asked, so there is no permission to have been granted silently.
    expect(await CalendarService.instance.requestPermission(), isFalse);
  });

  test('an install that said yes on an older build does not inherit a yes',
      () async {
    // What an upgrade from a build without the sheet looks like: a calendar id
    // already stored, and no consent key anywhere.
    SharedPreferences.setMockInitialValues({'om_calendar_id': 'work-cal-1'});
    await CalendarConsent.clear();

    expect(await CalendarConsent.isGranted(), isFalse);
    expect(await CalendarService.instance.requestPermission(), isFalse);
  });

  test('clearing on account switch re-closes the gate', () async {
    SharedPreferences.setMockInitialValues(
        {'om_calendar_consent_granted': true});
    expect(await CalendarConsent.isGranted(), isTrue);

    // The next account is a different person whose calendar this is not.
    await CalendarConsent.clear();
    expect(await CalendarConsent.isGranted(), isFalse);
    expect(await CalendarService.instance.requestPermission(), isFalse);
  });
}
