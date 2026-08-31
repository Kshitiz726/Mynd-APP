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

/// Where a looping track sits after [elapsed] of continuous playing.
///
/// A room's playhead is "time since this track started", which keeps growing
/// past the end of the track once it repeats. Wrapping it by the track length
/// is what makes every device land on the same second of the same repeat,
/// instead of seeking to a position the track does not have.
///
/// [elapsed] comes back unchanged while the length is unknown: the player
/// reports duration a moment after loading, and correcting against a guess is
/// worse than not correcting at all.
Duration loopedPosition(Duration elapsed, Duration trackLength) {
  if (trackLength <= Duration.zero) return elapsed;
  if (elapsed <= Duration.zero) return Duration.zero;
  return Duration(
    milliseconds: elapsed.inMilliseconds % trackLength.inMilliseconds,
  );
}
