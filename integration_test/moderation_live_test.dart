import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ourmynd/core/services/api_client.dart';
import 'package:ourmynd/core/services/session_store.dart';
import 'package:ourmynd/models/community/blocked_user.dart';

/// End to end, on a real device, against the live server.
///
/// The widget tests prove the rows are wired up. They cannot prove the thing
/// that was actually reported - "I don't have blocked contacts so won't load" -
/// because that failure is a round trip: a session out of the keychain, a
/// request to Render, and a table that has to exist in the database behind it.
/// A mocked test would have passed the whole time this was broken.
///
/// Needs a device with a signed-in session. It says so rather than passing
/// quietly if there is none, because a green run that proved nothing is worse
/// than a red one.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the blocked list loads for a real session against the live API',
      (tester) async {
    final restored = await SessionStore.restore();
    expect(restored, isTrue,
        reason: 'no session on this device - sign in first, or this test '
            'proves nothing');

    final api = ApiClient.instance;

    // Both halves of Guideline 1.2 are probed before anything is asserted, so
    // one run says which of them the live database can actually serve. They
    // come from the same migration, so they fail together or not at all - and
    // "blocking is broken" and "blocking and reporting are both broken" are
    // different sentences to have to act on.
    Object? blockErr;
    Object? reportErr;
    try {
      final probe = await api.fetchBlocked();
      debugPrint('[e2e] blocked list loaded, ${probe.length} entries');
    } catch (e) {
      blockErr = e;
      debugPrint('[e2e] BLOCK LIST FAILED: $e');
    }
    try {
      // A self-report is rejected by validation, not by the schema, so this
      // reaches the table without leaving a real report behind.
      await api.reportContent(
        targetType: 'user',
        targetId: '00000000-0000-0000-0000-000000000000',
        reason: 'spam',
      );
    } catch (e) {
      reportErr = e;
      debugPrint('[e2e] report probe returned: $e');
    }

    expect(blockErr, isNull, reason: 'the blocked list must load');
    expect(reportErr.toString().contains('does not exist'), isFalse,
        reason: 'the reports table must exist');

    List<BlockedUser> list = await api.fetchBlocked();

    // 2. Block somebody, and see them appear. Any real account will do, and
    //    the one guaranteed to exist is whoever is already blocked; failing
    //    that the round trip is still proven by the read above.
    if (list.isEmpty) {
      debugPrint('[e2e] nothing blocked - read path proven, write path skipped');
      return;
    }

    final victim = list.first;
    await api.unblockUser(victim.id);
    final after = await api.fetchBlocked();
    expect(after.any((b) => b.id == victim.id), isFalse,
        reason: 'unblock did not take effect on the server');

    await api.blockUser(victim.id);
    final again = await api.fetchBlocked();
    expect(again.any((b) => b.id == victim.id), isTrue,
        reason: 'block did not take effect on the server');
    debugPrint('[e2e] block and unblock both round-tripped');
  });
}
