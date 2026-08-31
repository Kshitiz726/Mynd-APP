import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/utils/music_playback.dart';

void main() {
  PlayerLoadAction call({
    bool isPlaylist = false,
    bool sessionRunning = true,
    bool roomPaused = false,
  }) =>
      playerLoadAction(
        isPlaylist: isPlaylist,
        sessionRunning: sessionRunning,
        roomPaused: roomPaused,
      );

  test('a running session plays a newly chosen track', () {
    expect(call(), PlayerLoadAction.loadVideo);
    expect(call(isPlaylist: true), PlayerLoadAction.loadPlaylist);
  });

  // The regression this file exists for. Switching the focus scene wraps the
  // screen in a Stack, which rebuilds the music card from scratch. A plain
  // load autoplays, so the music came back on underneath a paused timer.
  test('a paused session does not restart the music on a rebuild', () {
    expect(call(sessionRunning: false), PlayerLoadAction.cueVideo);
    expect(call(sessionRunning: false, isPlaylist: true),
        PlayerLoadAction.cuePlaylist);
  });

  test('a room-wide stop wins over a running timer', () {
    expect(call(roomPaused: true), PlayerLoadAction.cueVideo);
    expect(call(roomPaused: true, isPlaylist: true),
        PlayerLoadAction.cuePlaylist);
  });

  test('both suppressors at once still only cues', () {
    expect(call(sessionRunning: false, roomPaused: true),
        PlayerLoadAction.cueVideo);
  });

  test('playlist-ness never changes whether it plays, only what loads', () {
    for (final running in [true, false]) {
      for (final paused in [true, false]) {
        final video = call(sessionRunning: running, roomPaused: paused);
        final list =
            call(isPlaylist: true, sessionRunning: running, roomPaused: paused);
        final videoPlays = video == PlayerLoadAction.loadVideo;
        final listPlays = list == PlayerLoadAction.loadPlaylist;
        expect(videoPlays, listPlays,
            reason: 'running=$running paused=$paused disagreed');
      }
    }
  });

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
