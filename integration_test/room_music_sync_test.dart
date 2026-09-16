import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ourmynd/core/services/api_client.dart';
import 'package:ourmynd/core/services/realtime_service.dart';
import 'package:ourmynd/providers/focus_room_provider.dart';

/// Two real app instances in one focus room, checking that it is one room
/// rather than two people looking at their own copy of it.
///
/// Three claims are under test, all of them things the code already looked
/// like it did:
///   1. music one person sets arrives at the other,
///   2. a pause by one is a pause for both,
///   3. each side can see who else is in the room.
///
/// Role A joins and only observes. Role B does everything. Pass BD_ROLE=a|b.
const _role = String.fromEnvironment('BD_ROLE');

Future<T> _until<T>(
  String what,
  Future<T?> Function() probe, {
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final v = await probe();
    if (v != null) return v;
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  throw GaveUpWaiting(what);
}

class GaveUpWaiting implements Exception {
  GaveUpWaiting(this.what);
  final String what;
  @override
  String toString() => 'gave up waiting for: $what';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a focus room is one room: music, pause and people all shared',
      (tester) async {
    expect(_role, anyOf('a', 'b'));
    final api = ApiClient.instance;
    final rt = RealtimeService.instance;

    await api.authWithGoogle(
        handle: 'room_$_role', displayName: 'Room $_role');
    rt.connect();
    await rt.ensureConnected();

    final room = FocusRoomProvider();

    // Pair the two instances, which is what gives them a room to share.
    String? roomId;
    rt.on('bd_matched', (d) => roomId = d['roomId'] as String?);

    if (_role == 'a') {
      for (var i = 0; i < 140 && roomId == null; i++) {
        final m = await api.bodyDoublingMatch();
        if (m.matched) roomId = m.roomId;
        if (roomId != null) break;
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    } else {
      await Future<void>.delayed(const Duration(seconds: 14));
      for (var i = 0; i < 12 && roomId == null; i++) {
        final m = await api.bodyDoublingMatch();
        if (m.matched) roomId = m.roomId;
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    }
    expect(roomId, isNotNull, reason: 'the two instances never paired');
    debugPrint('[room:$_role] room $roomId');

    room.joinRoom(roomId!);

    // 3. Both sides should see two people.
    final people = await _until<int>('two participants', () async =>
        room.participantCount >= 2 ? room.participantCount : null);
    debugPrint('[room:$_role] participants=$people '
        '${room.participants.map((p) => p.displayName).toList()}');

    if (_role == 'b') {
      // Search by name, exactly as the music bar now does.
      final hits = await api.searchMusic('lofi study');
      expect(hits, isNotEmpty, reason: 'search by name returned nothing');
      debugPrint('[room:b] search best match: ${hits.first.label}');

      await Future<void>.delayed(const Duration(seconds: 3));
      await room.setMusic(hits.first.url, title: hits.first.label);
      debugPrint('[room:b] set music, local uri=${room.music?.uri}');

      await Future<void>.delayed(const Duration(seconds: 6));
      room.setMusicPaused(true);
      debugPrint('[room:b] asked for pause');
      await Future<void>.delayed(const Duration(seconds: 12));
      debugPrint('[room:b] paused locally = ${room.music?.paused}');
      expect(room.music?.paused, isTrue);
    } else {
      // 1. B's track has to arrive here without this side doing anything.
      final uri = await _until<String>('music set by the other person',
          () async => room.music?.uri);
      debugPrint('[room:a] received music uri=$uri title=${room.music?.title}');
      expect(uri, contains('stream:audio:'),
          reason: 'a searched track should arrive as a playable audio stream');

      // 2. And so does their pause.
      await _until<bool>('the pause to arrive',
          () async => room.music?.paused == true ? true : null);
      debugPrint('[room:a] pause arrived, paused=${room.music?.paused}');
    }

    await room.leaveRoom();
    debugPrint('[room:$_role] PASS');
  });
}
