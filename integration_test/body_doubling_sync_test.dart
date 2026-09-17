import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ourmynd/core/services/api_client.dart';
import 'package:ourmynd/core/services/realtime_service.dart';
import 'package:ourmynd/models/focus_mode.dart';
import 'package:ourmynd/providers/focus_provider.dart';
import 'package:ourmynd/providers/focus_room_provider.dart';

/// Body doubling from the Focus tab, which is the route people actually take.
///
/// The earlier room test drove FocusRoomProvider.joinRoom directly and passed,
/// which is why this bug survived it: that is the OTHER way into a room. Press
/// start with body doubling on and you get FocusProvider instead, and it used
/// to join only the socket - so the music, the ambience and the people all
/// arrived and were dropped, and each side fell back to reading music off its
/// own device. Two people in "the same room" heard different songs and neither
/// could pause the other.
///
/// Role A starts a session and watches. Role B starts one, and once they are
/// paired, sets the music and the scene. Pass BD_ROLE=a|b.
const _role = String.fromEnvironment('BD_ROLE');

Future<T> _until<T>(String what, Future<T?> Function() probe,
    {Duration timeout = const Duration(seconds: 260)}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final v = await probe();
    if (v != null) return v;
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  throw StateError('gave up waiting for: $what');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a body doubling session shares its music and its scene',
      (tester) async {
    expect(_role, anyOf('a', 'b'));
    final api = ApiClient.instance;
    await api.authWithGoogle(handle: 'bd2_$_role', displayName: 'BD2 $_role');
    RealtimeService.instance.connect();
    await RealtimeService.instance.ensureConnected();

    final rooms = FocusRoomProvider();
    final focus = FocusProvider()..bindRooms(rooms);

    if (_role == 'b') {
      await Future<void>.delayed(const Duration(seconds: 14));
    }
    focus.start(FocusMode.presets.first, true);

    // The whole point: starting a paired session must put this side in the
    // shared room, not merely on the socket.
    final roomId = await _until<String>('the shared room to be joined',
        () async => rooms.activeRoomId);
    expect(focus.bdRoomId, roomId);
    debugPrint('[bd2:$_role] in shared room $roomId');

    if (_role == 'b') {
      final hits = await api.searchMusic('lofi study');
      expect(hits, isNotEmpty);
      await Future<void>.delayed(const Duration(seconds: 3));
      await rooms.setMusic(hits.first.url, title: hits.first.label);
      rooms.setAmbience('rain');
      debugPrint('[bd2:b] set music "${hits.first.label}" and scene rain');
      await Future<void>.delayed(const Duration(seconds: 10));
      expect(rooms.music, isNotNull);
    } else {
      final uri = await _until<String>('music from the other person',
          () async => rooms.music?.uri);
      debugPrint('[bd2:a] heard about ${rooms.music?.title}');
      expect(uri, contains('stream:audio:'));

      await _until<bool>('the scene to follow',
          () async => rooms.ambience == 'rain' ? true : null);
      debugPrint('[bd2:a] scene is now ${rooms.ambience}');
    }

    focus.end();
    debugPrint('[bd2:$_role] PASS');
  });
}
