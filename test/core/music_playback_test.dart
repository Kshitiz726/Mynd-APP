import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/utils/music_playback.dart';

void main() {
  group('loopedPosition', () {
    test('leaves a position inside the track alone', () {
      expect(
        loopedPosition(const Duration(seconds: 40), const Duration(minutes: 3)),
        const Duration(seconds: 40),
      );
    });

    // The reason this exists: a room's playhead counts time since the track
    // started and never resets, so on the second time round it is past the
    // end. Wrapping is what keeps everyone on the same second of the same
    // repeat instead of seeking somewhere the track does not go.
    test('wraps onto the right second of a later repeat', () {
      const len = Duration(minutes: 3);
      expect(loopedPosition(const Duration(minutes: 3), len), Duration.zero);
      expect(loopedPosition(const Duration(seconds: 200), len),
          const Duration(seconds: 20));
      expect(loopedPosition(const Duration(minutes: 31), len),
          const Duration(minutes: 1));
    });

    test('an unknown length means no correction, not a crash', () {
      expect(loopedPosition(const Duration(seconds: 90), Duration.zero),
          const Duration(seconds: 90));
      expect(
        loopedPosition(const Duration(seconds: 90), const Duration(seconds: -5)),
        const Duration(seconds: 90),
      );
    });

    test('clocks that disagree land at the start, never before it', () {
      expect(loopedPosition(const Duration(seconds: -30),
          const Duration(minutes: 3)), Duration.zero);
    });
  });
}
