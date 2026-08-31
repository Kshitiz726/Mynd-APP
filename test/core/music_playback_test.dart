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
}
