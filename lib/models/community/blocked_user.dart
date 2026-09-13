/// Somebody this account has blocked.
///
/// Only the blocks *you* made are ever listed: this backs an unblock screen,
/// and you cannot undo somebody else's decision. Filtering still reads both
/// directions - see the server's notBlockedSql.
class BlockedUser {
  const BlockedUser({
    required this.id,
    required this.displayName,
    required this.handle,
    required this.initial,
    required this.avatarColor,
    required this.blockedAt,
  });

  final String id;
  final String displayName;
  final String handle;
  final String initial;
  final String avatarColor;
  final DateTime blockedAt;

  factory BlockedUser.fromJson(Map<String, dynamic> j) => BlockedUser(
        id: j['id'] as String,
        displayName: (j['display_name'] ?? '') as String,
        handle: (j['handle'] ?? '') as String,
        initial: (j['initial'] ?? '?') as String,
        avatarColor: (j['avatar_color'] ?? '#6366F1') as String,
        blockedAt:
            DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now(),
      );
}
