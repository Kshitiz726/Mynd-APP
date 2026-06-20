/// A friend in the body-doubling invite list (from `GET /api/friends`).
class BdFriend {
  BdFriend({
    required this.id,
    required this.name,
    required this.initial,
    required this.color,
    required this.status,
  });

  final String id;
  final String name;
  final String initial;
  final String? color;
  final String status;

  bool get accepted => status == 'accepted';

  factory BdFriend.fromJson(Map<String, dynamic> j) => BdFriend(
        id: j['id'] as String,
        name: (j['display_name'] ?? 'Friend') as String,
        initial: (j['initial'] ?? '?') as String,
        color: j['avatar_color'] as String?,
        status: (j['status'] ?? 'pending') as String,
      );
}

/// The matched partner returned by the matchmaker / socket `bd_matched`.
class BdPartner {
  BdPartner({required this.id, required this.name, required this.initial, required this.color});

  final String id;
  final String name;
  final String initial;
  final String? color;

  factory BdPartner.fromJson(Map<String, dynamic> j) => BdPartner(
        // server sends camelCase for sockets/REST partner payloads
        id: j['id'] as String,
        name: (j['displayName'] ?? j['display_name'] ?? 'Partner') as String,
        initial: (j['initial'] ?? '?') as String,
        color: (j['avatarColor'] ?? j['avatar_color']) as String?,
      );
}

/// Result of POST /api/body-doubling/match: either paired now, or queued.
class BdMatch {
  BdMatch({required this.matched, this.roomId, this.partner});

  final bool matched;
  final String? roomId;
  final BdPartner? partner;
}
