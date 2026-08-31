/// How a freshly loaded track should be handed to the player.
///
/// Pulled out of the widget because getting this wrong is silent and hard to
/// see: the difference between `load` and `cue` is whether the video starts
/// playing, and a wrong choice only shows up as music coming back on when it
/// should not have.
library;

enum PlayerLoadAction {
  /// Load and begin playing.
  loadVideo,

  /// Prepare, but stay silent until something asks for playback.
  cueVideo,
  loadPlaylist,
  cuePlaylist,
}

/// Decide how to load, from the two things that can suppress playback.
///
/// [sessionRunning] is the focus timer. A paused timer means the listener has
/// stepped away, and a track that restarts itself under a paused timer is the
/// bug this function exists to prevent: switching the scene rebuilds the card
/// from scratch, and a plain `load` autoplays regardless of what the timer is
/// doing.
///
/// [roomPaused] is the room-wide stop, which is authoritative for everyone.
PlayerLoadAction playerLoadAction({
  required bool isPlaylist,
  required bool sessionRunning,
  required bool roomPaused,
}) {
  final play = sessionRunning && !roomPaused;
  if (isPlaylist) {
    return play ? PlayerLoadAction.loadPlaylist : PlayerLoadAction.cuePlaylist;
  }
  return play ? PlayerLoadAction.loadVideo : PlayerLoadAction.cueVideo;
}
