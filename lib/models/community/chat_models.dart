import '../../core/services/api_config.dart';

/// An ADHD community group (e.g. "ADHD Students"). Each group has exactly one
/// backing chat conversation, opened lazily when a user joins.
class Group {
  Group({
    required this.id,
    required this.name,
    required this.iconName,
    required this.iconColor,
    required this.memberCount,
    required this.joined,
    this.conversationId,
  });

  final String id;
  final String name;
  final String iconName;
  final String iconColor;
  final int memberCount;
  final bool joined;

  /// Set for joined groups so tapping opens the chat with no extra round-trip.
  final String? conversationId;

  String get membersLabel {
    if (memberCount >= 1000) return '${(memberCount / 1000).toStringAsFixed(1)}k members';
    return '$memberCount members';
  }

  Group copyWith({int? memberCount, bool? joined, String? conversationId}) => Group(
        id: id,
        name: name,
        iconName: iconName,
        iconColor: iconColor,
        memberCount: memberCount ?? this.memberCount,
        joined: joined ?? this.joined,
        conversationId: conversationId ?? this.conversationId,
      );

  factory Group.fromJson(Map<String, dynamic> j) => Group(
        id: j['id'] as String,
        name: (j['name'] ?? 'Group') as String,
        iconName: (j['icon_name'] ?? 'users') as String,
        iconColor: (j['icon_color'] ?? '#6B70C9') as String,
        memberCount: (j['member_count'] ?? 0) as int,
        joined: j['joined'] == true,
        conversationId: j['conversation_id'] as String?,
      );
}

/// A row in the Chats tab — a group chat or a 1:1 DM.
class ChatConversation {
  ChatConversation({
    required this.id,
    required this.isGroup,
    required this.title,
    this.iconName,
    this.iconColor,
    this.lastMessage,
    this.unread = 0,
    this.peerId,
    this.peerInitial,
    this.peerColor,
  });

  final String id;
  final bool isGroup;
  final String title;
  final String? iconName;
  final String? iconColor;
  final String? lastMessage;
  final int unread;
  final String? peerId;
  final String? peerInitial;
  final String? peerColor;

  ChatConversation copyWith({String? lastMessage, int? unread}) => ChatConversation(
        id: id,
        isGroup: isGroup,
        title: title,
        iconName: iconName,
        iconColor: iconColor,
        lastMessage: lastMessage ?? this.lastMessage,
        unread: unread ?? this.unread,
        peerId: peerId,
        peerInitial: peerInitial,
        peerColor: peerColor,
      );

  factory ChatConversation.fromJson(Map<String, dynamic> j) {
    final isGroup = j['is_group'] == true;
    final lastKind = j['last_kind'] as String?;
    final lastBody = j['last_message'] as String?;
    final preview = switch (lastKind) {
      'image' => '📷 Photo',
      'file' => '📎 File',
      _ => lastBody,
    };
    return ChatConversation(
      id: j['id'] as String,
      isGroup: isGroup,
      title: (isGroup ? (j['group_name'] ?? 'Group') : (j['peer_name'] ?? 'Direct message')) as String,
      iconName: j['group_icon'] as String?,
      iconColor: j['group_color'] as String?,
      lastMessage: preview,
      // Postgres count(*) comes back as a bigint string — coerce safely.
      unread: int.tryParse('${j['unread'] ?? 0}') ?? 0,
      peerId: j['peer_id'] as String?,
      peerInitial: j['peer_initial'] as String?,
      peerColor: j['peer_color'] as String?,
    );
  }
}

enum MsgKind { text, image, file }

/// Optimistic lifecycle of a locally-originated message.
enum SendStatus { sending, sent, failed }

MsgKind _kindFrom(String? s) => switch (s) {
      'image' => MsgKind.image,
      'file' => MsgKind.file,
      _ => MsgKind.text,
    };

/// One chat message. Sender info is denormalised so group chats can show who
/// said what without extra lookups. May carry media (image/file).
class ChatMsg {
  ChatMsg({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.body,
    required this.senderName,
    required this.senderInitial,
    this.senderColor,
    this.kind = MsgKind.text,
    this.mediaUrl,
    this.mediaMeta,
    this.clientTempId,
    this.replyToId,
    this.replyToBody,
    this.replyToSender,
    this.status = SendStatus.sent,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String conversationId;
  final String senderId;
  final String body;
  final String senderName;
  final String senderInitial;
  final String? senderColor;
  final MsgKind kind;
  final String? mediaUrl;
  final Map<String, dynamic>? mediaMeta;
  final String? clientTempId;
  final String? replyToId;
  final String? replyToBody;
  final String? replyToSender;
  final SendStatus status;
  final DateTime createdAt;

  bool get mine => senderId == ApiConfig.instance.userId;
  bool get isMedia => kind != MsgKind.text;

  ChatMsg copyWith({String? id, SendStatus? status, String? mediaUrl}) => ChatMsg(
        id: id ?? this.id,
        conversationId: conversationId,
        senderId: senderId,
        body: body,
        senderName: senderName,
        senderInitial: senderInitial,
        senderColor: senderColor,
        kind: kind,
        mediaUrl: mediaUrl ?? this.mediaUrl,
        mediaMeta: mediaMeta,
        clientTempId: clientTempId,
        replyToId: replyToId,
        replyToBody: replyToBody,
        replyToSender: replyToSender,
        status: status ?? this.status,
        createdAt: createdAt,
      );

  factory ChatMsg.fromJson(Map<String, dynamic> j) => ChatMsg(
        id: j['id'] as String,
        conversationId: j['conversation_id'] as String,
        senderId: j['sender_id'] as String,
        body: (j['body'] ?? '') as String,
        senderName: (j['sender_name'] ?? '') as String,
        senderInitial: (j['sender_initial'] ?? '?') as String,
        senderColor: j['sender_color'] as String?,
        kind: _kindFrom(j['kind'] as String?),
        mediaUrl: j['media_url'] as String?,
        mediaMeta: (j['media_meta'] as Map?)?.cast<String, dynamic>(),
        clientTempId: j['client_temp_id'] as String?,
        replyToId: j['reply_to_id'] as String?,
        replyToBody: j['reply_to_body'] as String?,
        replyToSender: j['reply_to_sender'] as String?,
        status: SendStatus.sent,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      );

  /// Optimistic local echo while the server round-trips.
  factory ChatMsg.local(
    String conversationId,
    String tempId, {
    String body = '',
    MsgKind kind = MsgKind.text,
    String? mediaUrl,
    Map<String, dynamic>? mediaMeta,
    String? replyToId,
    String? replyToBody,
    String? replyToSender,
  }) {
    final cfg = ApiConfig.instance;
    final name = cfg.displayName ?? 'You';
    return ChatMsg(
      id: tempId,
      conversationId: conversationId,
      senderId: cfg.userId ?? '',
      body: body,
      senderName: name,
      senderInitial: name.isEmpty ? 'Y' : name.substring(0, 1).toUpperCase(),
      kind: kind,
      mediaUrl: mediaUrl,
      mediaMeta: mediaMeta,
      clientTempId: tempId,
      replyToId: replyToId,
      replyToBody: replyToBody,
      replyToSender: replyToSender,
      status: SendStatus.sending,
    );
  }
}

/// An incoming follow request, shown in the Alerts dashboard.
class FollowRequest {
  FollowRequest({
    required this.userId,
    required this.displayName,
    required this.initial,
    this.avatarColor,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String userId;
  final String displayName;
  final String initial;
  final String? avatarColor;
  final DateTime createdAt;

  factory FollowRequest.fromJson(Map<String, dynamic> j) => FollowRequest(
        userId: j['id'] as String,
        displayName: (j['display_name'] ?? 'Someone') as String,
        initial: (j['initial'] ?? '?') as String,
        avatarColor: j['avatar_color'] as String?,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal(),
      );
}

/// A persisted notification row from the alerts inbox.
class AppNotification {
  AppNotification({
    required this.id,
    required this.kind,
    required this.payload,
    required this.read,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  final String kind;
  final Map<String, dynamic> payload;
  final bool read;
  final DateTime createdAt;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        kind: kind,
        payload: payload,
        read: read ?? this.read,
        createdAt: createdAt,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        kind: (j['kind'] ?? '') as String,
        payload: (j['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
        read: j['read_at'] != null,
        createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '')?.toLocal(),
      );
}

/// A member of a conversation/group — public identity only (no email).
class ConversationMember {
  ConversationMember({
    required this.id,
    required this.displayName,
    required this.initial,
    this.avatarColor,
    this.isMe = false,
  });

  final String id;
  final String displayName;
  final String initial;
  final String? avatarColor;
  final bool isMe;

  factory ConversationMember.fromJson(Map<String, dynamic> j) => ConversationMember(
        id: j['id'] as String,
        displayName: (j['display_name'] ?? 'Member') as String,
        initial: (j['initial'] ?? '?') as String,
        avatarColor: j['avatar_color'] as String?,
        isMe: j['is_me'] == true,
      );
}

/// A user profile for the in-chat profile sheet.
class UserProfile {
  UserProfile({
    required this.id,
    required this.displayName,
    required this.initial,
    this.handle,
    this.avatarColor,
    this.isMe = false,
    this.friendStatus,
    this.outgoing = false,
    this.canDm = false,
  });

  final String id;
  final String displayName;
  final String initial;
  final String? handle;
  final String? avatarColor;
  final bool isMe;
  final String? friendStatus; // pending | accepted | rejected | null
  final bool outgoing;
  final bool canDm;

  factory UserProfile.fromJson(Map<String, dynamic> j) {
    final u = (j['user'] as Map).cast<String, dynamic>();
    final f = (j['friendship'] as Map?)?.cast<String, dynamic>();
    return UserProfile(
      id: u['id'] as String,
      displayName: (u['display_name'] ?? 'Someone') as String,
      initial: (u['initial'] ?? '?') as String,
      handle: u['handle'] as String?,
      avatarColor: u['avatar_color'] as String?,
      isMe: j['isMe'] == true,
      friendStatus: f?['status'] as String?,
      outgoing: f?['outgoing'] == true,
      canDm: j['canDm'] == true,
    );
  }
}
