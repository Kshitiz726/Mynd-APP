import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/account_scope.dart';

/// "Delete my account" used to leave everything on the device. The server row
/// was the only thing that went, and even that failed - so signing back in
/// handed the whole account back and the deletion looked like it had been
/// ignored.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const me = 'user-aaa';
  const them = 'user-bbb';

  test('a switch parks data, because handing over a phone must not cost it',
      () async {
    SharedPreferences.setMockInitialValues({
      'om_local_data_owner': me,
      'om_tasks': 'my tasks',
    });

    await AccountScope.adopt(them);
    final p = await SharedPreferences.getInstance();

    expect(p.getString('om_tasks'), isNull, reason: 'the new account saw it');
    expect(p.getString('omacct:$me:om_tasks'), 'my tasks',
        reason: 'a switch must not destroy the outgoing account\'s data');
  });

  test('a purge destroys it, live and parked', () async {
    // The opposite of a switch, and deliberately so: somebody told their
    // account is gone has not been told the truth if it is still on the device
    // under another key, waiting to be handed back.
    SharedPreferences.setMockInitialValues({
      'om_local_data_owner': me,
      'om_tasks': 'my tasks',
      'om_goals': 'my goals',
      'om_user_memory': 'what it knows about me',
      'omacct:$me:om_mood_entries': 'parked from an earlier session',
      'omacct:$them:om_tasks': 'somebody else, still parked',
      'om_notif_permission_asked': 'true',
    });

    await AccountScope.purge(me);
    final p = await SharedPreferences.getInstance();

    for (final k in ['om_tasks', 'om_goals', 'om_user_memory']) {
      expect(p.getString(k), isNull, reason: '$k survived the deletion');
    }
    expect(p.getString('omacct:$me:om_mood_entries'), isNull,
        reason: 'a parked copy is still a copy');
    expect(p.getString('om_local_data_owner'), isNull);

    // Somebody else's parked data is not this account's to delete.
    expect(p.getString('omacct:$them:om_tasks'), 'somebody else, still parked');
    // And a device-level fact is not personal data.
    expect(p.getString('om_notif_permission_asked'), 'true');
  });

  test('purging leaves nothing for the next sign-in to adopt', () async {
    // The reported symptom: delete the account, sign in again, everything is
    // back. It came back because it was never gone.
    SharedPreferences.setMockInitialValues({
      'om_local_data_owner': me,
      'om_tasks': 'my tasks',
    });

    await AccountScope.purge(me);
    await AccountScope.adopt('user-fresh-id');
    final p = await SharedPreferences.getInstance();

    expect(p.getString('om_tasks'), isNull);
  });
}
