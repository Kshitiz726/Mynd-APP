/// What a room is currently playing.
///
/// Mirrors the server's RoomMusic (server/src/realtime/presence.ts). The room
/// agrees on a URI; each device plays its own copy through its own Spotify, so
/// this is shared STATE, not shared audio. Positions drift between people and
/// the UI says so rather than implying otherwise.
class RoomMusic {
  const RoomMusic({
    required this.uri,
    required this.title,
    required this.changedBy,
    required this.changedAt,
  });

  /// Always canonical `spotify:{kind}:{id}` - the server normalises before it
  /// broadcasts, so nothing downstream has to cope with share links.
  final String uri;

  /// Cosmetic label, may be absent. Server-capped and stripped of control
  /// characters, because whoever set it chose the text.
  final String? title;

  final String changedBy;
  final DateTime changedAt;

  /// What to show when there is no title: the kind and a short id beats an
  /// empty row, and beats showing the whole URI.
  String get displayLabel {
    if (title != null && title!.isNotEmpty) return title!;
    final parts = uri.split(':');
    if (parts.length == 3) {
      final kind = parts[1];
      return '${kind[0].toUpperCase()}${kind.substring(1)} · ${parts[2].substring(0, 6)}…';
    }
    return uri;
  }

  /// The https form, for handing to the OS when Spotify is not installed.
  Uri get webUrl {
    final parts = uri.split(':');
    return parts.length == 3
        ? Uri.parse('https://open.spotify.com/${parts[1]}/${parts[2]}')
        : Uri.parse('https://open.spotify.com');
  }

  static RoomMusic? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final uri = j['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    final at = j['changedAt'];
    return RoomMusic(
      uri: uri,
      title: j['title'] as String?,
      changedBy: j['changedBy'] as String? ?? '',
      changedAt: at is int
          ? DateTime.fromMillisecondsSinceEpoch(at)
          : DateTime.now(),
    );
  }
}
