import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ourmynd/core/services/api_client.dart';
import 'package:ourmynd/core/services/realtime_service.dart';

/// Two real app instances, one on each simulator, against a real server.
///
/// The thing being proved is that a block survives the queue. Blocking someone
/// you have just been paired with is worth nothing if pressing "find someone"
/// again hands you straight back to them, and matchmaking is the one surface in
/// this app that puts a stranger and a live microphone in the same room.
///
/// Roles are picked with --dart-define=BD_ROLE=a|b. A waits in the queue and
/// listens for the socket push; B does the matching, the blocking, and the
/// second attempt that must not pair them again.
const _role = String.fromEnvironment('BD_ROLE');
const _handleA = 'bdtest_a';
const _handleB = 'bdtest_b';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a block keeps you out of each other\'s matchmaking',
      (tester) async {
    expect(_role, anyOf('a', 'b'), reason: 'pass --dart-define=BD_ROLE=a|b');
    final api = ApiClient.instance;

    if (_role == 'a') {
      await api.authWithGoogle(handle: _handleA, displayName: 'BD Test A');
      RealtimeService.instance.connect();
      await RealtimeService.instance.ensureConnected();

      var matched = false;
      RealtimeService.instance.on('bd_matched', (_) => matched = true);

      // Hold a place in the queue for as long as B needs. Re-queueing is what
      // makes this survive being pulled out by a pairing.
      for (var i = 0; i < 240; i++) {
        await api.bodyDoublingMatch();
        await Future<void>.delayed(const Duration(seconds: 3));
        debugPrint('[bd:a] tick $i matched=$matched');
      }
      debugPrint('[bd:a] done, matched at least once = $matched');
      expect(matched, isTrue,
          reason: 'A never received bd_matched - pairing itself is broken');
      return;
    }

    // ── Role B ──
    await api.authWithGoogle(handle: _handleB, displayName: 'BD Test B');
    RealtimeService.instance.connect();
    await RealtimeService.instance.ensureConnected();

    // Give A time to be in the queue.
    await Future<void>.delayed(const Duration(seconds: 12));

    // 1. Pair with A.
    var m = await api.bodyDoublingMatch();
    for (var i = 0; i < 10 && !m.matched; i++) {
      await Future<void>.delayed(const Duration(seconds: 3));
      m = await api.bodyDoublingMatch();
    }
    expect(m.matched, isTrue, reason: 'never paired with A in the first place');
    final partnerId = m.partner!.id;
    debugPrint('[bd:b] paired with ${m.partner!.name} ($partnerId)');

    // 2. Block them, exactly as the "Report or block" row on the paired
    //    screen does.
    await api.blockUser(partnerId);
    final blocked = await api.fetchBlocked();
    expect(blocked.any((b) => b.id == partnerId), isTrue,
        reason: 'the block did not persist');
    debugPrint('[bd:b] blocked, list now has ${blocked.length}');

    // 3. Queue again, repeatedly. A is still in the queue and is the only
    //    other person there, so any pairing at all is a pairing with A.
    await api.bodyDoublingCancel();
    for (var i = 0; i < 8; i++) {
      final again = await api.bodyDoublingMatch();
      expect(again.matched, isFalse,
          reason: 'matched with a blocked account on attempt $i');
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    debugPrint('[bd:b] never re-paired with the blocked account');

    // Leave the fixture clean so the next run starts from the same place.
    await api.unblockUser(partnerId);
    await api.bodyDoublingCancel();
  });
}
