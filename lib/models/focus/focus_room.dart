/// A focus room as listed in the Rooms tab. Live counts come from the server's
/// Redis presence layer, not the durable row.
class FocusRoom {
  FocusRoom({
    required this.id,
    required this.title,
    required this.iconName,
    required this.iconColor,
    required this.liveCount,
    required this.defaultAmbience,
    required this.livekitRoom,
    this.visibility = 'public',
    this.hostId,
    this.code,
  });

  final String id;
  final String title;
  final String iconName;     // 'coffee', 'brain', 'keyboard'
  final String iconColor;    // hex
  final int liveCount;       // "38 people focusing"
  final String defaultAmbience;
  final String livekitRoom;
  final String visibility;   // 'public' | 'private'
  final String? hostId;

  /// The short join code, e.g. 4K9P. The only way into a private room, and a
  /// sayable way into a public one.
  final String? code;

  bool get isPublic => visibility == 'public';
  String get label => '$liveCount people focusing';

  /// Returns a copy with an updated live participant count.
  FocusRoom withCount(int count) => FocusRoom(
        id: id, title: title, iconName: iconName, iconColor: iconColor,
        liveCount: count, defaultAmbience: defaultAmbience, livekitRoom: livekitRoom,
        visibility: visibility, hostId: hostId, code: code,
      );

  factory FocusRoom.fromJson(Map<String, dynamic> j) => FocusRoom(
        id: j['id'] as String,
        title: j['title'] as String,
        iconName: j['icon_name'] as String? ?? 'brain',
        iconColor: j['icon_color'] as String? ?? '#6366F1',
        liveCount: j['liveCount'] as int? ?? 0,
        defaultAmbience: j['default_ambience'] as String? ?? 'cafe',
        livekitRoom: j['livekit_room'] as String? ?? '',
        visibility: j['visibility'] as String? ?? 'public',
        hostId: j['host_id'] as String?,
        code: j['code'] as String?,
      );
}
