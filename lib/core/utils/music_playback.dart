/// Playback maths that is easier to get wrong than to read.
library;

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
