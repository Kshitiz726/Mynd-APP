import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../utils/music_link.dart';

/// Look up the human name of a track, so a session says "Yabesh Thapa -
/// Kasari" instead of "Video · vnHTrx…".
///
/// oEmbed, because it is the documented public endpoint for exactly this on
/// both providers: no key, no account, no quota to manage, and it returns only
/// what any link preview would show. It never touches the media itself.
///
/// Every failure is silent and returns null. A missing title costs a nicer
/// label; it must never cost the music, so a dead network, a private video or
/// a provider changing its mind all fall back to the id-based label rather
/// than surfacing an error nobody can act on.
Future<String?> fetchMusicTitle(MusicLink link) async {
  // A file and a direct stream carry their name in the path already, and
  // asking a stranger's server about a local file would be both pointless and
  // a small privacy leak.
  final endpoint = switch (link.provider) {
    MusicProvider.youtube =>
      'https://www.youtube.com/oembed?format=json&url=${Uri.encodeComponent(link.webUrl.toString())}',
    MusicProvider.spotify =>
      'https://open.spotify.com/oembed?url=${Uri.encodeComponent(link.webUrl.toString())}',
    MusicProvider.stream || MusicProvider.file => null,
  };
  if (endpoint == null) return null;

  try {
    // Short, because this runs between pasting a link and hearing anything. A
    // slow lookup must not become a slow play button.
    final res = await http
        .get(Uri.parse(endpoint))
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    if (body is! Map) return null;
    final title = body['title'];
    if (title is! String) return null;
    return tidyMusicTitle(title);
  } catch (e) {
    debugPrint('[focus-music] title lookup failed: $e');
    return null;
  }
}

/// Trim a title down to something that fits on one line of a pill.
///
/// Uploaders pad titles with the things a search engine wants and a listener
/// does not: "(Official Music Video)", "[HD]", "| Lyrics". Stripping the
/// common tails leaves the name of the song, which is the only part anyone
/// reads mid-session.
String? tidyMusicTitle(String raw) {
  var t = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Repeated, because a title can carry several of these in a row.
  for (var i = 0; i < 4; i++) {
    final before = t;
    t = t
        .replaceAll(
            RegExp(
              r'[\(\[]\s*(official\s*)?(music\s*)?(lyrics?\s*)?'
              r'(video|audio|lyrics?|visualizer|mv|hd|hq|4k|full\s*song)'
              r'\s*[\)\]]\s*$',
              caseSensitive: false,
            ),
            '')
        .replaceAll(
            RegExp(
              r'\|\s*(official\s*)?(music\s*)?(lyrics?\s*)?'
              r'(video|audio|lyrics?|visualizer)\s*$',
              caseSensitive: false,
            ),
            '')
        .trim();
    if (t == before) break;
  }
  // Never return an empty string: a title that was nothing but decoration is
  // worse than the id-based label, which at least identifies the track.
  return t.isEmpty ? null : t;
}
