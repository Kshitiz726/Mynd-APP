/// One track that came back from a search by name.
///
/// [url] is deliberately a plain https URL on our own server rather than
/// anything provider shaped: it ends in .mp3, so it passes the same stream
/// check as a link somebody pasted, and it is the identical string for every
/// person in a room. Nothing downstream needs to know a search happened.
class MusicSearchResult {
  const MusicSearchResult({
    required this.id,
    required this.title,
    required this.artist,
    required this.url,
    this.durationSecs,
    this.artworkUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String url;
  final int? durationSecs;
  final String? artworkUrl;

  /// What to show once it is playing. The artist matters here: two tracks can
  /// share a name, and "who is this" is the first thing you wonder when the
  /// wrong one starts.
  String get label => artist.isEmpty ? title : '$title - $artist';

  static MusicSearchResult? fromJson(Map<String, dynamic> j) {
    final id = j['id'] as String?;
    final title = j['title'] as String?;
    final url = j['url'] as String?;
    if (id == null || title == null || url == null) return null;
    return MusicSearchResult(
      id: id,
      title: title,
      artist: (j['artist'] as String?) ?? '',
      url: url,
      durationSecs: (j['durationSecs'] as num?)?.toInt(),
      artworkUrl: j['artworkUrl'] as String?,
    );
  }
}
