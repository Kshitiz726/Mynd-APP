import '../core/utils/music_link.dart';

/// What a room is currently playing.
///
/// Mirrors the server's RoomMusic (server/src/realtime/presence.ts).
///
/// What "playing" means depends on the provider, and the UI has to say so:
///   - YouTube plays inside Mynd, and [startedAt] lets everyone line up to the
///     same position, so the room really is listening together.
///   - Spotify cannot play inside any third-party app on mobile, so it is
///     shared STATE only - everyone opens it in their own Spotify and drifts.
class RoomMusic {
  const RoomMusic({
    required this.uri,
    required this.title,
    required this.changedBy,
    required this.changedAt,
    this.startedAt,
    this.paused = false,
    this.positionMs = 0,
  });

  /// Always canonical `{provider}:{kind}:{id}` - the server normalises before
  /// it broadcasts, so nothing downstream has to cope with share links.
  final String uri;

  /// Cosmetic label, may be absent. Server-capped and stripped of control
  /// characters, because whoever set it chose the text.
  final String? title;

  final String changedBy;
  final DateTime changedAt;

  /// Server clock reading for "position zero" of this track. Everyone computes
  /// their seek offset from it, so nobody's local clock skew becomes the
  /// room's. Null for providers we cannot position (Spotify).
  final DateTime? startedAt;

  final bool paused;

  /// Where the playhead was frozen, meaningful only while [paused].
  final int positionMs;

  /// The parsed link, or null if the server sent something this build does not
  /// understand. Callers must handle null rather than assuming: an older app
  /// can be in a room with a newer one that set a provider it has never
  /// heard of.
  MusicLink? get link => MusicLink.parse(uri);

  bool get playsInApp => link?.playsInApp ?? false;

  /// Where the playhead should be right now, from the server's clock.
  ///
  /// Late joiners land at the right second instead of starting from zero. A
  /// negative or absurd value means the clocks disagree badly enough not to
  /// trust, so it falls back to the start rather than seeking somewhere wrong.
  Duration positionAt(DateTime now) {
    if (paused) return Duration(milliseconds: positionMs);
    if (startedAt == null) return Duration.zero;
    final d = now.difference(startedAt!);
    if (d.isNegative || d > const Duration(hours: 12)) return Duration.zero;
    return d;
  }

  /// What to show when there is no title: the kind and a short id beats an
  /// empty row, and beats showing the whole URI.
  String get displayLabel {
    if (title != null && title!.isNotEmpty) return title!;
    final l = link;
    if (l == null) return uri;
    // A file name beats "Audio . aHR0cH..." for anything carrying one.
    final name = l.fileLabel;
    if (name != null && name.isNotEmpty) return name;
    final kind = '${l.kind[0].toUpperCase()}${l.kind.substring(1)}';
    final id = l.id.length > 6 ? '${l.id.substring(0, 6)}…' : l.id;
    return '$kind · $id';
  }

  /// The https form, for handing to the OS.
  Uri get webUrl => link?.webUrl ?? Uri.parse('https://www.youtube.com');

  static RoomMusic? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final uri = j['uri'] as String?;
    if (uri == null || uri.isEmpty) return null;
    return RoomMusic(
      uri: uri,
      title: j['title'] as String?,
      changedBy: j['changedBy'] as String? ?? '',
      changedAt: _time(j['changedAt']) ?? DateTime.now(),
      startedAt: _time(j['startedAt']),
      paused: j['paused'] == true,
      positionMs: j['positionMs'] is int ? j['positionMs'] as int : 0,
    );
  }

  static DateTime? _time(dynamic v) =>
      v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
}
