import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import 'package:http/http.dart' as http;

import 'account_scope.dart';
import 'api_config.dart';
import 'session_store.dart';
import '../../models/community/post.dart';
import '../../models/community/chat_models.dart';
import '../../models/focus/focus_room.dart';
import '../../models/focus/body_double.dart';

/// REST client for the OurMynd backend. Mirrors `server/src/routes/*`.
/// Follows the same singleton style as [GroqService].
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  final _client = http.Client();
  ApiConfig get _cfg => ApiConfig.instance;

  Future<Map<String, dynamic>> _get(String path) async {
    final res = await _client.get(_cfg.rest(path), headers: _cfg.authHeaders);
    return _decode(res);
  }

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res =
        await _client.post(_cfg.rest(path), headers: _cfg.authHeaders, body: jsonEncode(body));
    return _decode(res);
  }

  Future<Map<String, dynamic>> get(String path) => _get(path);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) => _post(path, body);

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) async {
    final res = await _client.put(_cfg.rest(path), headers: _cfg.authHeaders, body: jsonEncode(body));
    return _decode(res);
  }

  Future<Map<String, dynamic>> delete(String path) async {
    final res = await _client.delete(_cfg.rest(path), headers: _cfg.authHeaders);
    return _decode(res);
  }

  /// Called once when the server rejects our session, so the app can send the
  /// user back to the login screen. Set in main().
  static void Function()? onSessionExpired;

  /// Guards against a burst of 401s (every provider refreshing at once) tearing
  /// the session down repeatedly and firing the callback for each one.
  bool _expiring = false;

  Map<String, dynamic> _decode(http.Response res) {
    if (res.statusCode >= 400) {
      // A 401 means this token is no longer anything the server accepts:
      // expired, signed out elsewhere, or - the case that actually bit us -
      // minted by a DIFFERENT backend. Pointing the app at the hosted server
      // left every device holding a token signed with the old local secret, so
      // every request failed while the app still believed it was signed in.
      // Nothing sent the user back to login, so it just looked like the
      // features were broken: matchmaking, feed and chat all failing with
      // vague "couldn't do that" toasts and no way to recover short of
      // reinstalling.
      if (res.statusCode == 401 && !_expiring) {
        _expiring = true;
        // Fire and forget: callers are mid-request and should still get their
        // exception, they just should not also be left signed in.
        signOut().whenComplete(() {
          _expiring = false;
          onSessionExpired?.call();
        });
      }
      throw ApiException('${res.statusCode}: ${res.body}', res.statusCode);
    }
    if (res.body.isEmpty) return {};
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  // ── Auth ──
  /// Real Google sign-in: hands the server a Google ID token, which it verifies
  /// and exchanges for our own session JWT + the (created-or-existing) user.
  Future<void> authWithGoogleIdToken(String idToken) async {
    final j = await _post('/api/auth/google', {'idToken': idToken});
    await _applyUser(j);
  }

  /// Real Sign in with Apple: hands the backend the identity token Apple gave
  /// the app. The server checks it against Apple's published keys and our
  /// bundle id, then returns our own session JWT + user, same as Google.
  Future<void> authWithAppleIdentityToken(String identityToken) async {
    final j = await _post('/api/auth/apple', {'identityToken': identityToken});
    await _applyUser(j);
  }

  /// Desktop (Windows/Linux) real Google OAuth: hands the backend the auth code
  /// from the loopback flow; the server exchanges it (with the desktop client
  /// secret) for an ID token, verifies it, and returns our session JWT + user.
  Future<void> authWithGoogleDesktop({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final j = await _post('/api/auth/google/desktop', {
      'code': code,
      'codeVerifier': codeVerifier,
      'redirectUri': redirectUri,
    });
    await _applyUser(j);
  }

  Future<void> authWithGoogle({required String handle, required String displayName}) async {
    final j = await _post('/api/auth/google-mock', {'handle': handle, 'displayName': displayName});
    await _applyUser(j);
  }

  Future<void> _applyUser(Map<String, dynamic> j) async {
    final user = j['user'] as Map<String, dynamic>;
    final userId = user['id'] as String;

    // Before this account can see anything, make the local data on this device
    // its own: park whoever had it, hand back this account's if it has been
    // here before. Runs first so the swap can never touch the session we are
    // about to write. See AccountScope.
    final switched = await AccountScope.adopt(userId);

    _cfg
      ..authToken = j['token'] as String
      ..userId = userId
      ..displayName = user['display_name'] as String?
      ..handle = user['handle'] as String?;
    // Persist so the next launch (or "continue with Google" again) restores the
    // whole account without re-authing.
    await SessionStore.save();

    // Swapping the keys is only half of it: the providers built at launch are
    // still holding the previous user's tasks and goals in memory, and would
    // write them straight back over the new account's. Rebuild the app once
    // the new session is in place, so everything reloads from disk.
    if (switched) AccountScope.onSwitched?.call();
  }

  /// Clear the in-memory + on-disk session. Used by sign out.
  Future<void> signOut() async {
    await SessionStore.clear();
    _cfg
      ..authToken = null
      ..userId = null
      ..displayName = null
      ..handle = null;
  }

  /// Fetches a dev JWT for a seeded user and wires [ApiConfig]. Dev only - in
  /// production this is replaced by the real Supabase Auth sign-in.
  Future<void> devSignIn({String user = 'sam'}) async {
    final j = await _get('/api/dev/token?user=$user');
    _cfg
      ..authToken = j['token'] as String
      ..userId = j['userId'] as String;
  }

  // ── Feed ──
  Future<({List<Post> posts, String? nextCursor})> fetchFeed({String? cursor, String? tag}) async {
    final q = <String, String>{};
    if (cursor != null) q['cursor'] = cursor;
    if (tag != null) q['tag'] = tag;
    final path = '/api/feed${q.isEmpty ? '' : '?${Uri(queryParameters: q).query}'}';
    final j = await _get(path);
    final posts = (j['posts'] as List).map((p) => Post.fromJson(p)).toList();
    return (posts: posts, nextCursor: j['nextCursor'] as String?);
  }

  Future<Post> createPost({required String body, String? mood, List<String> tags = const []}) async {
    final j = await _post('/api/posts', {'body': body, 'mood': mood, 'tags': tags});
    return Post.fromJson(j);
  }

  Future<void> reactRest(String postId, ReactionKind kind) =>
      _post('/api/posts/$postId/reactions', {'kind': kind.name});

  Future<PostComment> addComment(String postId, String body, {String? parentId}) async {
    final Map<String, dynamic> payload = {'body': body};
    if (parentId != null) payload['parentId'] = parentId;
    final j = await _post('/api/posts/$postId/comments', payload);
    return PostComment.fromJson(j.cast());
  }

  Future<void> toggleCommentUpvote(String commentId, bool active) =>
      _post('/api/comments/$commentId/upvote', {'active': active});

  Future<List<PostComment>> fetchComments(String postId) async {
    final j = await _get('/api/posts/$postId/comments');
    return (j['comments'] as List).map((c) => PostComment.fromJson((c as Map).cast())).toList();
  }

  // ── Rooms ──
  Future<({int globalLive, List<FocusRoom> rooms})> fetchRooms() async {
    final j = await _get('/api/rooms');
    final rooms = (j['rooms'] as List).map((r) => FocusRoom.fromJson(r)).toList();
    return (globalLive: j['globalLive'] as int? ?? 0, rooms: rooms);
  }

  Future<FocusRoom> createRoom({
    required String title,
    String iconName = 'brain',
    String iconColor = '#6366F1',
    String ambience = 'cafe',
    bool isPublic = true,
  }) async {
    final j = await _post('/api/rooms', {
      'title': title,
      'iconName': iconName,
      'iconColor': iconColor,
      'ambience': ambience,
      'visibility': isPublic ? 'public' : 'private',
    });
    return FocusRoom.fromJson(j);
  }
  /// Resolve a join code to a room.
  ///
  /// Throws when the code does not resolve. The server answers the same 404
  /// whether the room never existed, has ended, or is private and the code was
  /// a guess, so this cannot be used to enumerate private rooms.
  Future<FocusRoom> joinRoomByCode(String code) async {
    final j = await _post('/api/rooms/join-by-code', {'code': code});
    return FocusRoom.fromJson(j);
  }


  Future<void> completeSession(String roomId, int completedSecs) =>
      _post('/api/sessions/complete', {'roomId': roomId, 'completedSecs': completedSecs});

  // ── Social ──
  Future<void> sendFriendRequest(String userId) => _post('/api/friends/request', {'userId': userId});

  /// Respond to a follow request. On accept the server provisions the DM and
  /// returns its conversation id so the UI can unlock the chat immediately.
  Future<String?> respondFriendRequest(String requesterId, bool accept) async {
    final j = await _post('/api/friends/respond', {'requesterId': requesterId, 'accept': accept});
    return j['conversationId'] as String?;
  }

  Future<List<FollowRequest>> fetchFollowRequests() async {
    final j = await _get('/api/friends/requests');
    return (j['requests'] as List).map((x) => FollowRequest.fromJson((x as Map).cast())).toList();
  }

  Future<UserProfile> fetchUserProfile(String userId) async {
    final j = await _get('/api/users/$userId');
    return UserProfile.fromJson(j);
  }

  /// Full friends list (accepted both ways + pending), my POV.
  Future<List<BdFriend>> fetchFriends() async {
    final j = await _get('/api/friends');
    return (j['friends'] as List).map((f) => BdFriend.fromJson((f as Map).cast())).toList();
  }

  // ── Your own profile ──
  /// Everything about the signed-in account, including the parts only they see.
  Future<Map<String, dynamic>> fetchMe() async {
    final j = await _get('/api/me');
    return (j['user'] as Map).cast<String, dynamic>();
  }

  /// Change the name everyone else sees. Returns the updated profile.
  Future<Map<String, dynamic>> updateDisplayName(String name) async {
    final res = await _client.patch(_cfg.rest('/api/me'),
        headers: _cfg.authHeaders, body: jsonEncode({'displayName': name}));
    final j = _decode(res);
    final user = (j['user'] as Map).cast<String, dynamic>();
    // Keep the in-memory session in step, or the greeting on Home keeps using
    // the old name until the next launch.
    _cfg.displayName = user['display_name'] as String?;
    SessionStore.save();
    return user;
  }

  /// Set your profile picture. [bytes] is already-encoded image data.
  Future<void> uploadAvatar(Uint8List bytes, {String mime = 'image/jpeg'}) async {
    final res = await _client.put(
      _cfg.rest('/api/me/avatar'),
      headers: _cfg.authHeaders,
      body: jsonEncode({'data': base64Encode(bytes), 'mime': mime}),
    );
    _decode(res);
  }

  Future<void> removeAvatar() => delete('/api/me/avatar');

  // ── Per-account state (the backlog and friends follow the account) ──
  /// The document parked under [key], with when it was last written, so the
  /// caller can tell whether the server's copy or the phone's is the newer one.
  Future<({Object? value, DateTime? updatedAt})> fetchState(String key) async {
    final j = await _get('/api/state/$key');
    final at = j['updatedAt'] as String?;
    return (
      value: j['value'],
      updatedAt: at == null ? null : DateTime.tryParse(at),
    );
  }

  Future<void> putState(String key, Object value) =>
      put('/api/state/$key', {'value': value});

  // ── Body doubling ──
  /// Join the matchmaking queue. Either pairs immediately (matched=true with a
  /// room + partner) or queues you (matched=false) - `bd_matched` arrives over
  /// the socket when a partner shows up.
  Future<BdMatch> bodyDoublingMatch() async {
    final j = await _post('/api/body-doubling/match', {});
    return BdMatch(
      matched: j['matched'] == true,
      roomId: j['roomId'] as String?,
      partner: j['partner'] == null ? null : BdPartner.fromJson((j['partner'] as Map).cast()),
    );
  }

  Future<void> bodyDoublingCancel() => _post('/api/body-doubling/cancel', {});

  /// Invite a friend to a new body-doubling room; returns the room id.
  Future<String> bodyDoublingInvite(String userId) async {
    final j = await _post('/api/body-doubling/invite', {'userId': userId});
    return j['roomId'] as String;
  }

  // ── Groups ──
  /// Exactly N (default 5) unjoined groups - the "Groups for you" rail.
  Future<List<Group>> fetchSuggestedGroups({int limit = 5}) async {
    final j = await _get('/api/groups/suggested?limit=$limit');
    return (j['groups'] as List).map((g) => Group.fromJson((g as Map).cast())).toList();
  }

  /// Groups the user has joined - "Your groups".
  Future<List<Group>> fetchMyGroups() async {
    final j = await _get('/api/groups/mine');
    return (j['groups'] as List).map((g) => Group.fromJson((g as Map).cast())).toList();
  }

  Future<List<Group>> fetchGroups() async {
    final j = await _get('/api/groups');
    return (j['groups'] as List).map((g) => Group.fromJson((g as Map).cast())).toList();
  }

  /// Join a group (idempotent) and get its chat conversation id.
  Future<String> joinGroup(String groupId) async {
    final j = await _post('/api/groups/$groupId/join', {});
    return j['conversationId'] as String;
  }

  /// Resolve a group's chat without changing membership (bug-proof open path).
  /// Falls back through join so an already-member always gets a valid id.
  Future<String> openGroupChat(String groupId) async {
    final j = await _get('/api/groups/$groupId/conversation');
    final id = j['conversationId'] as String?;
    if (id == null) throw ApiException('no conversation for group $groupId', 500);
    return id;
  }

  // ── Notifications / alerts ──
  Future<({List<AppNotification> items, int unread})> fetchNotifications() async {
    final j = await _get('/api/notifications');
    final items =
        (j['notifications'] as List).map((n) => AppNotification.fromJson((n as Map).cast())).toList();
    return (items: items, unread: j['unread'] as int? ?? 0);
  }

  Future<void> markNotificationsRead({List<String>? ids}) async =>
      _post('/api/notifications/read', {if (ids != null) 'ids': ids});

  // ── Chat ──
  Future<List<ChatConversation>> fetchConversations() async {
    final j = await _get('/api/conversations');
    return (j['conversations'] as List).map((c) => ChatConversation.fromJson((c as Map).cast())).toList();
  }

  Future<List<ChatMsg>> fetchMessages(String conversationId) async {
    final j = await _get('/api/conversations/$conversationId/messages');
    return (j['messages'] as List).map((m) => ChatMsg.fromJson((m as Map).cast())).toList();
  }

  /// Members of a conversation (group roster) - public identity only, no email.
  Future<List<ConversationMember>> fetchConversationMembers(String conversationId) async {
    final j = await _get('/api/conversations/$conversationId/members');
    return (j['members'] as List)
        .map((m) => ConversationMember.fromJson((m as Map).cast()))
        .toList();
  }

  /// Open (or create) a 1:1 DM with a user; returns the conversation id.
  Future<String> openDirect(String userId) async {
    final j = await _post('/api/conversations/direct', {'userId': userId});
    return j['id'] as String;
  }

  Future<void> markRead(String conversationId) async =>
      _post('/api/conversations/$conversationId/read', {});
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => 'ApiException($message)';
}
