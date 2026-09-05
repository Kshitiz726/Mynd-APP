import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/models/room_music.dart';

void main() {
  RoomMusic music({DateTime? startedAt, bool paused = false, int positionMs = 0}) =>
      RoomMusic(
        uri: 'youtube:video:dQw4w9WgXcQ',
        title: null,
        changedBy: '',
        changedAt: DateTime.now(),
        startedAt: startedAt,
        paused: paused,
        positionMs: positionMs,
      );

  final now = DateTime.now();

  // The regression. startedAt is the ROOM's shared clock. A solo session has
  // no room, so setting it to "when you picked the track" made positionAt grow
  // without bound - and seeking there landed past the end of any track shorter
  // than the session, which stopped the audio silently.
  test('no room clock means start at the beginning', () {
    expect(music(startedAt: null).positionAt(now), Duration.zero);
  });

  test('a room clock gives the shared position', () {
    final started = now.subtract(const Duration(minutes: 3));
    expect(music(startedAt: started).positionAt(now).inSeconds, closeTo(180, 2));
  });

  test('a paused room holds its frozen position', () {
    expect(
      music(startedAt: null, paused: true, positionMs: 42000).positionAt(now),
      const Duration(seconds: 42),
    );
  });

  group('clock disagreement falls back to the start rather than seeking wrong', () {
    test('a start time in the future', () {
      final ahead = now.add(const Duration(minutes: 5));
      expect(music(startedAt: ahead).positionAt(now), Duration.zero);
    });

    test('an absurdly old start time', () {
      final ancient = now.subtract(const Duration(days: 2));
      expect(music(startedAt: ancient).positionAt(now), Duration.zero);
    });
  });
}
