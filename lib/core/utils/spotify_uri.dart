/// Canonicalise whatever a human pasted into a Spotify URI.
///
/// Deliberately duplicated on the server (server/src/realtime/spotify_uri.ts).
/// The client copy is for telling someone immediately that what they pasted is
/// not a Spotify link; the server copy is the one that decides what gets
/// broadcast to a room. Neither trusts the other.
library;

const _kinds = {'track', 'album', 'playlist', 'artist', 'show', 'episode'};

/// Spotify ids are base62 and 22 characters in practice. Bounded rather than
/// pinned to 22, because that length is an observation, not a guarantee.
final _id = RegExp(r'^[A-Za-z0-9]{16,40}$');
final _uri = RegExp(r'^spotify:([a-z]+):([A-Za-z0-9]+)$');

/// Hard ceiling before parsing, so a pasted essay is cheap to reject.
const _maxInput = 400;

/// Returns a canonical `spotify:{kind}:{id}`, or null if this is not one.
String? normaliseSpotifyUri(String? input) {
  if (input == null) return null;
  final raw = input.trim();
  if (raw.isEmpty || raw.length > _maxInput) return null;

  final m = _uri.firstMatch(raw);
  if (m != null) {
    final kind = m.group(1)!;
    final id = m.group(2)!;
    return _kinds.contains(kind) && _id.hasMatch(id) ? 'spotify:$kind:$id' : null;
  }

  final url = Uri.tryParse(raw);
  if (url == null) return null;
  if (url.scheme != 'https' && url.scheme != 'http') return null;
  // Exact host match, not endsWith: `open.spotify.com.example.net` is not
  // Spotify, and a suffix check would have accepted it.
  if (url.host != 'open.spotify.com' && url.host != 'play.spotify.com') {
    return null;
  }

  final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
  // Drop a leading locale segment: /intl-de/playlist/{id}.
  if (parts.isNotEmpty && parts.first.startsWith('intl-')) parts.removeAt(0);
  if (parts.length < 2) return null;

  final kind = parts[0];
  final id = parts[1];
  // The query is dropped on purpose. `?si=` is a share token identifying the
  // person who sent the link; storing it would leak that to every participant.
  return _kinds.contains(kind) && _id.hasMatch(id) ? 'spotify:$kind:$id' : null;
}
