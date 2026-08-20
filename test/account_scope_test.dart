import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/account_scope.dart';

/// Two people, one phone. The rule is that neither ever sees the other's
/// schedule, and neither ever loses it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('a new account sees none of the previous account\'s data', () async {
    final p = await SharedPreferences.getInstance();
    await p.setString('om_tasks', "alice's tasks");
    await p.setString('om_goals', "alice's goals");
    await AccountScope.adopt('alice');

    await AccountScope.adopt('bob');

    expect(p.getString('om_tasks'), isNull);
    expect(p.getString('om_goals'), isNull);
  });

  test('an account gets its own data back when it returns', () async {
    final p = await SharedPreferences.getInstance();
    await AccountScope.adopt('alice');
    await p.setString('om_tasks', "alice's tasks");
    await p.setInt('om_focus_seconds', 1500);
    await p.setStringList('om_streak_days', ['2026-08-13', '2026-08-14']);

    await AccountScope.adopt('bob');
    await p.setString('om_tasks', "bob's tasks");

    await AccountScope.adopt('alice');

    expect(p.getString('om_tasks'), "alice's tasks");
    expect(p.getInt('om_focus_seconds'), 1500);
    expect(p.getStringList('om_streak_days'), ['2026-08-13', '2026-08-14']);
  });

  test("the other account's data survives the round trip too", () async {
    final p = await SharedPreferences.getInstance();
    await AccountScope.adopt('alice');
    await p.setString('om_tasks', "alice's tasks");
    await AccountScope.adopt('bob');
    await p.setString('om_tasks', "bob's tasks");
    await AccountScope.adopt('alice');

    await AccountScope.adopt('bob');

    expect(p.getString('om_tasks'), "bob's tasks");
  });

  test('signing in as the same account changes nothing', () async {
    final p = await SharedPreferences.getInstance();
    await AccountScope.adopt('alice');
    await p.setString('om_tasks', "alice's tasks");

    expect(await AccountScope.adopt('alice'), isFalse);
    expect(p.getString('om_tasks'), "alice's tasks");
  });

  test('the session and the permission flag stay put across a switch', () async {
    final p = await SharedPreferences.getInstance();
    await AccountScope.adopt('alice');
    await p.setString('om_session_token', 'jwt');
    await p.setBool('om_notif_permission_asked', true);

    await AccountScope.adopt('bob');

    expect(p.getString('om_session_token'), 'jwt');
    expect(p.getBool('om_notif_permission_asked'), isTrue);
  });

  test('data from before accounts were tracked is kept, not handed over',
      () async {
    final p = await SharedPreferences.getInstance();
    await p.setString('om_tasks', 'nobody knows whose');

    await AccountScope.adopt('alice');

    expect(p.getString('om_tasks'), isNull, reason: 'alice must not inherit it');
    expect(
      p.getKeys().where((k) => k.contains('_unclaimed')),
      isNotEmpty,
      reason: 'but it must still be on the device',
    );
  });
}
