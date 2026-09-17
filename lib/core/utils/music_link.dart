/// Canonicalise whatever a human pasted into a music link we can act on.
///
/// Deliberately duplicated on the server (server/src/realtime/music_link.ts).
/// The client copy is for telling someone immediately that what they pasted is
/// not a link we understand; the server copy is the one that decides what gets
/// broadcast to a room. Neither trusts the other.
///
/// The canonical form is `{provider}:{kind}:{id}` for both providers, so
/// everything downstream - Redis, the socket payload, the stored solo
/// preference - handles one shape of string.
library;

import 'dart:convert';

/// Where the audio comes from, which decides how it can be played.
///
/// This is the whole reason the two providers are not interchangeable:
/// YouTube can be embedded and played inside the app, Spotify cannot. See
/// [MusicLink.playsInApp].
/// - [stream] is a direct audio URL: an mp3, an m4a, an HLS manifest, an
///   internet-radio endpoint. It is the only provider that plays as pure
///   audio, with no video surface anywhere, because it IS just audio.
/// - [file] is an audio file on this device. Solo only, and deliberately never
///   sent to a room: a local path is meaningless on someone else's phone and
///   broadcasting one would leak the owner's filesystem layout - and often
///   their name - to every participant.
enum MusicProvider { spotify, youtube, stream, file }

/// A link we recognised, broken into its parts.
class MusicLink {
  const MusicLink({
    required this.provider,
    required this.kind,
    required this.id,
  });

  final MusicProvider provider;

  /// Spotify: track/album/playlist/artist/show/episode.
  /// YouTube: video/playlist.
  final String kind;

  final String id;

  /// `spotify:playlist:{id}` or `youtube:video:{id}`.
  String get uri => '${provider.name}:$kind:$id';

  /// Whether we can play this inside Mynd, or can only hand it to another app.
  ///
  /// Only audio we are actually entitled to stream: a direct audio URL, a file
  /// on the device, or a track from the search catalogue, which resolves to a
  /// direct URL.
  ///
  /// YouTube is handed over rather than embedded. Their API Terms require the
  /// embedded player to stay visible and unobscured, and a focus timer has
  /// nowhere to put a video - the only way to keep it playing under the timer
  /// was to hide it, which is precisely what those terms forbid. Spotify
  /// cannot be embedded at all on mobile: the Web Playback SDK needs
  /// EME/Widevine and is unsupported in a webview, and the App Remote SDK is a
  /// remote control for the Spotify app rather than a source of audio.
  ///
  /// Both therefore degrade honestly to a hand-off, and the bar says so rather
  /// than letting someone find out by pressing play.
  bool get playsInApp =>
      provider != MusicProvider.spotify && provider != MusicProvider.youtube;

  /// Whether this can be shared with a room. A device file cannot.
  bool get shareable => provider != MusicProvider.file;

  /// Whether this plays with no video surface at all.
  ///
  /// The same set as [playsInApp], and deliberately still its own name: one
  /// answers "are we allowed to play this here", the other "does playing it
  /// need somewhere to put a picture". They coincide today because the only
  /// thing we embed is audio.
  bool get audioOnly =>
      provider == MusicProvider.stream || provider == MusicProvider.file;

  /// The playable URL for [MusicProvider.stream], or the local path for
  /// [MusicProvider.file]. Both are base64url encoded in the canonical form so
  /// the `{provider}:{kind}:{id}` shape survives colons and slashes.
  String? get streamUrl => switch (provider) {
        MusicProvider.stream || MusicProvider.file =>
          utf8.decode(base64Url.decode(base64Url.normalize(id))),
        _ => null,
      };

  /// Local path for [MusicProvider.file].
  String? get filePath =>
      provider == MusicProvider.file ? streamUrl : null;

  /// The https form, for handing to the OS.
  Uri get webUrl => switch (provider) {
        MusicProvider.spotify =>
          Uri.parse('https://open.spotify.com/$kind/$id'),
        MusicProvider.youtube => kind == 'playlist'
            ? Uri.parse('https://www.youtube.com/playlist?list=$id')
            : Uri.parse('https://www.youtube.com/watch?v=$id'),
        MusicProvider.stream => Uri.parse(streamUrl!),
        MusicProvider.file => Uri.file(streamUrl!),
      };

  /// Cover art for the disc, or null where the provider does not give us one
  /// without an authenticated API call (Spotify).
  ///
  /// hqdefault exists for every video and never 404s to a placeholder the way
  /// maxresdefault does for anything not uploaded in HD.
  String? get artworkUrl => switch (provider) {
        MusicProvider.youtube when kind == 'video' =>
          'https://img.youtube.com/vi/$id/hqdefault.jpg',
        _ => null,
      };

  /// What to call this when there is no title. A file name is the only
  /// human-readable thing a stream or a local file carries.
  String? get fileLabel {
    final url = streamUrl;
    if (url == null) return null;
    if (provider == MusicProvider.file) return url.split('/').last;
    final segs = Uri.tryParse(url)?.pathSegments.where((s) => s.isNotEmpty);
    if (segs == null || segs.isEmpty) return Uri.tryParse(url)?.host;
    return Uri.decodeComponent(segs.last);
  }

  /// Rebuild from a canonical string, or null if it is not one. Used when
  /// reading back something the server or shared preferences stored.
  static MusicLink? parse(String? canonical) {
    if (canonical == null) return null;
    final parts = canonical.split(':');
    if (parts.length != 3) return null;
    return switch (parts[0]) {
      'spotify' => _spotifyKinds.contains(parts[1]) && _spotifyId.hasMatch(parts[2])
          ? MusicLink(provider: MusicProvider.spotify, kind: parts[1], id: parts[2])
          : null,
      'youtube' => _youtube(parts[1], parts[2]),
      'stream' => _stream(parts[1], parts[2]),
      'file' => _file(parts[1], parts[2]),
      _ => null,
    };
  }
}

const _spotifyKinds = {'track', 'album', 'playlist', 'artist', 'show', 'episode'};

/// Spotify ids are base62 and 22 characters in practice. Bounded rather than
/// pinned to 22, because that length is an observation, not a guarantee.
final _spotifyId = RegExp(r'^[A-Za-z0-9]{16,40}$');

/// YouTube video ids are exactly 11 characters of the URL-safe alphabet. That
/// one IS documented and stable, so it is pinned.
final _ytVideoId = RegExp(r'^[A-Za-z0-9_-]{11}$');

/// Playlist ids vary by type (PL/UU/LL/RD/OL/FL prefixes, plus the "WL" and
/// "LL" specials which are private and will not embed anyway).
final _ytPlaylistId = RegExp(r'^[A-Za-z0-9_-]{12,42}$');

final _spotifyUriRe = RegExp(r'^spotify:([a-z]+):([A-Za-z0-9]+)$');

const _spotifyHosts = {'open.spotify.com', 'play.spotify.com'};

/// youtu.be is the share shortener; music.youtube.com serves the same ids.
const _youtubeHosts = {
  'youtube.com',
  'www.youtube.com',
  'm.youtube.com',
  'music.youtube.com',
};
const _youtubeShortHosts = {'youtu.be', 'www.youtu.be'};

/// Hard ceiling before parsing, so a pasted essay is cheap to reject.
const _maxInput = 400;

/// Audio containers and manifests worth accepting.
///
/// An extension is required rather than accepting any URL: without one there
/// is no way to tell an audio endpoint from an HTML page, and handing the
/// player a web page produces a silent failure that looks like a bug.
const _audioExt = {
  'mp3', 'm4a', 'aac', 'ogg', 'oga', 'opus', 'flac', 'wav', 'weba',
  'm3u8', 'pls',
};

/// Build a link for an audio file this device already holds.
///
/// Not reachable from [parseMusicLink]: there is no pasted text that should
/// ever become a local path, and accepting one would be a way to point the
/// player at an arbitrary file. It is constructed only from the file picker.
MusicLink? musicLinkForFile(String path) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  final name = trimmed.split('/').last.toLowerCase();
  final dot = name.lastIndexOf('.');
  if (dot < 0 || !_audioExt.contains(name.substring(dot + 1))) return null;
  return MusicLink(
    provider: MusicProvider.file,
    kind: 'audio',
    id: base64Url.encode(utf8.encode(trimmed)).replaceAll('=', ''),
  );
}

MusicLink? _file(String kind, String id) {
  if (kind != 'audio') return null;
  try {
    return musicLinkForFile(
        utf8.decode(base64Url.decode(base64Url.normalize(id))));
  } catch (_) {
    return null;
  }
}

MusicLink? _stream(String kind, String id) {
  if (kind != 'audio') return null;
  try {
    final url = utf8.decode(base64Url.decode(base64Url.normalize(id)));
    return _streamFromUrl(Uri.tryParse(url));
  } catch (_) {
    return null;
  }
}

MusicLink? _streamFromUrl(Uri? url) {
  if (url == null) return null;
  if (url.scheme != 'https' && url.scheme != 'http') return null;
  if (url.host.isEmpty) return null;
  final segs = url.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segs.isEmpty) return null;
  final last = segs.last.toLowerCase();
  final dot = last.lastIndexOf('.');
  if (dot < 0) return null;
  if (!_audioExt.contains(last.substring(dot + 1))) return null;
  // The query is kept: stream endpoints routinely carry a required token or
  // bitrate selector, and dropping it would break the URL.
  final canonical = url.toString();
  return MusicLink(
    provider: MusicProvider.stream,
    kind: 'audio',
    id: base64Url.encode(utf8.encode(canonical)).replaceAll('=', ''),
  );
}

MusicLink? _youtube(String kind, String id) {
  if (kind == 'video' && _ytVideoId.hasMatch(id)) {
    return MusicLink(provider: MusicProvider.youtube, kind: 'video', id: id);
  }
  if (kind == 'playlist' && _ytPlaylistId.hasMatch(id)) {
    return MusicLink(provider: MusicProvider.youtube, kind: 'playlist', id: id);
  }
  return null;
}

/// Parse a pasted link or canonical URI. Null means "not something we play".
MusicLink? parseMusicLink(String? input) {
  if (input == null) return null;
  final raw = input.trim();
  if (raw.isEmpty || raw.length > _maxInput) return null;

  // Already canonical, or a spotify: URI.
  final direct = MusicLink.parse(raw);
  if (direct != null) return direct;

  final m = _spotifyUriRe.firstMatch(raw);
  if (m != null) {
    final kind = m.group(1)!;
    final id = m.group(2)!;
    return _spotifyKinds.contains(kind) && _spotifyId.hasMatch(id)
        ? MusicLink(provider: MusicProvider.spotify, kind: kind, id: id)
        : null;
  }

  final url = Uri.tryParse(raw);
  if (url == null) return null;
  if (url.scheme != 'https' && url.scheme != 'http') return null;

  // Exact host match, not endsWith: `open.spotify.com.example.net` is not
  // Spotify, and a suffix check would have accepted it.
  final host = url.host.toLowerCase();
  if (_spotifyHosts.contains(host)) return _fromSpotifyUrl(url);
  if (_youtubeHosts.contains(host)) return _fromYoutubeUrl(url);
  if (_youtubeShortHosts.contains(host)) {
    final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
    // youtu.be/{id}. The `?si=` and `?t=` are dropped with the query.
    return parts.length == 1 ? _youtube('video', parts.first) : null;
  }
  // Anything else is only interesting if it points straight at audio.
  return _streamFromUrl(url);
}

MusicLink? _fromSpotifyUrl(Uri url) {
  final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
  // Drop a leading locale segment: /intl-de/playlist/{id}.
  if (parts.isNotEmpty && parts.first.startsWith('intl-')) parts.removeAt(0);
  if (parts.length < 2) return null;

  final kind = parts[0];
  final id = parts[1];
  // The query is dropped on purpose. `?si=` is a share token identifying the
  // person who sent the link; storing it would leak that to every participant.
  return _spotifyKinds.contains(kind) && _spotifyId.hasMatch(id)
      ? MusicLink(provider: MusicProvider.spotify, kind: kind, id: id)
      : null;
}

MusicLink? _fromYoutubeUrl(Uri url) {
  final parts = url.pathSegments.where((s) => s.isNotEmpty).toList();
  final v = url.queryParameters['v'];
  final list = url.queryParameters['list'];

  // /watch?v={id}. A watch URL can also carry ?list=, but the video is what
  // the sender was looking at, so it wins.
  if (parts.isNotEmpty && parts.first == 'watch' && v != null) {
    return _youtube('video', v);
  }
  // /playlist?list={id}
  if (parts.isNotEmpty && parts.first == 'playlist' && list != null) {
    return _youtube('playlist', list);
  }
  // /shorts/{id}, /embed/{id}, /live/{id} all carry a plain video id.
  if (parts.length >= 2 &&
      const {'shorts', 'embed', 'live', 'v'}.contains(parts.first)) {
    return _youtube('video', parts[1]);
  }
  // A bare ?v= with no path, and the list-only fallback.
  if (v != null) return _youtube('video', v);
  if (list != null) return _youtube('playlist', list);
  return null;
}

/// The canonical string, or null. Convenience for callers that only store it.
String? normaliseMusicUri(String? input) => parseMusicLink(input)?.uri;
