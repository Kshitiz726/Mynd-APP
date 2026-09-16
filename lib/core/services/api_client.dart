import 'dart:convert';
import 'dart:typed_data' show Uint8List;
import 'package:http/http.dart' as http;

import 'account_scope.dart';
import 'api_config.dart';
import 'session_store.dart';
import '../../models/community/blocked_user.dart';
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

  /// Every request goes through here.
  ///
  /// Access tokens now last 30 minutes rather than 30 days, so a 401 is the
  /// normal, expected end of a token's life rather than a sign that the session
  /// is over. It is handled once, here: refresh, then replay the request. Only
  /// if the refresh itself fails does the user get sent back to sign-in.
  ///
  /// [send] is a closure rather than a prepared Request because it has to be
  /// runnable twice, with the *new* auth header the second time.
  Future<Map<String, dynamic>> _send(Future<http.Response> Function() send) async {
    var res = await send();
    if (res.statusCode == 401 && _cfg.refreshToken != null) {
      if (await refreshSession()) {
        res = await send();
      }
    }
    return _decode(res);
  }

  Future<Map<String, dynamic>> _get(String path) =>
      _send(() => _client.get(_cfg.rest(path), headers: _cfg.authHeaders));

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) => _send(
        () => _client.post(_cfg.rest(path), headers: _cfg.authHeaders, body: jsonEncode(body)),
      );

  Future<Map<String, dynamic>> get(String path) => _get(path);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) => _post(path, body);

  Future<Map<String, dynamic>> put(String path, Map<String, dynamic> body) => _send(
        () => _client.put(_cfg.rest(path), headers: _cfg.authHeaders, body: jsonEncode(body)),
      );

  Future<Map<String, dynamic>> delete(String path, [Map<String, dynamic>? body]) => _send(
        () => _client.delete(
          _cfg.rest(path),
          headers: _cfg.authHeaders,
          body: body == null ? null : jsonEncode(body),
        ),
      );

  /// Called once when the server rejects our session, so the app can send the
  /// user back to the login screen. Set in main().
  static void Function()? onSessionExpired;

  /// Guards against a burst of 401s (every provider refreshing at once) tearing
  /// the session down repeatedly and firing the callback for each one.
  bool _expiring = false;

  /// In-flight refresh, shared by every request that hits a 401 at once.
  ///
  /// Without this, a screen that fires six requests on open would run six
  /// refreshes, five of which race and lose - and since refresh rotates the
  /// token, the losers would install a stale one and fail again. One refresh,
  /// everybody awaits it.
  Future<bool>? _refreshing;

  /// Trade the refresh token for a new pair. Returns false if the session is
  /// genuinely finished and the user has to sign in again.
  ///
  /// Public because [GroqService] has to share it. That service talks to the
  /// same backend with the same session but its own http.Client, so without
  /// this it had no way to recover from a 401 - and sharing the single-flight
  /// future matters more than the visibility: a brain dump and a screenful of
  /// ApiClient requests expiring together must produce one refresh, not two
  /// racing ones where the loser installs a rotated, already-dead token.
  Future<bool> refreshSession() {
    return _refreshing ??= () async {
      try {
        final refresh = _cfg.refreshToken;
        if (refresh == null) return false;
        // Deliberately a bare client call, not _post: going through the normal
        // path would attach the dead access token and could recurse straight
        // back into this method on another 401.
        final res = await _client.post(
          _cfg.rest('/api/auth/refresh'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'refreshToken': refresh}),
        );
        if (res.statusCode >= 400) return false;
        final j = jsonDecode(res.body) as Map<String, dynamic>;
        _cfg
          ..authToken = j['token'] as String?
          ..refreshToken = j['refreshToken'] as String?;
        await SessionStore.save();
        return _cfg.authToken != null;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    }();
  }

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
        signOut(revokeRemotely: false).whenComplete(() {
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
  Future<bool> authWithGoogleIdToken(String idToken) async {
    final j = await _post('/api/auth/google', {'idToken': idToken});
    return _applyUser(j);
  }

  /// Real Sign in with Apple: hands the backend the identity token Apple gave
  /// the app. The server checks it against Apple's published keys and our
  /// bundle id, then returns our own session JWT + user, same as Google.
  Future<bool> authWithAppleIdentityToken(String identityToken) async {
    final j = await _post('/api/auth/apple', {'identityToken': identityToken});
    return _applyUser(j);
  }

  /// Desktop (Windows/Linux) real Google OAuth: hands the backend the auth code
  /// from the loopback flow; the server exchanges it (with the desktop client
  /// secret) for an ID token, verifies it, and returns our session JWT + user.
  Future<bool> authWithGoogleDesktop({
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final j = await _post('/api/auth/google/desktop', {
      'code': code,
      'codeVerifier': codeVerifier,
      'redirectUri': redirectUri,
    });
    return _applyUser(j);
  }

  Future<bool> authWithGoogle({required String handle, required String displayName}) async {
    final j = await _post('/api/auth/google-mock', {'handle': handle, 'displayName': displayName});
    return _applyUser(j);
  }

  /// Returns whether this sign-in replaced a different account's data on the
  /// device, which is the caller's cue to restart the app rather than navigate.
  Future<bool> _applyUser(Map<String, dynamic> j) async {
    final user = j['user'] as Map<String, dynamic>;
    final userId = user['id'] as String;

    // Before this account can see anything, make the local data on this device
    // its own: park whoever had it, hand back this account's if it has been
    // here before. Runs first so the swap can never touch the session we are
    // about to write. See AccountScope.
    final switched = await AccountScope.adopt(userId);

    _cfg
      ..authToken = j['token'] as String
      ..refreshToken = j['refreshToken'] as String?
      ..userId = userId
      ..displayName = user['display_name'] as String?
      ..handle = user['handle'] as String?;
    // Persist so the next launch (or "continue with Google" again) restores the
    // whole account without re-authing.
    await SessionStore.save();

    // Swapping the keys is only half of it: the providers built at launch are
    // still holding the previous user's tasks and goals in memory, and would
    // write them straight back over the new account's. The app has to be
    // rebuilt from the root for that to clear.
    //
    // Deliberately NOT done here. This used to call AccountScope.onSwitched
    // itself, which tore the widget tree down in the middle of an await the
    // login screen was still sitting on - and that screen then went on to
    // navigate and setState through a context whose tree had just been
    // replaced. Signing in as a second account therefore threw on the way in
    // and only worked on the retry, by which point the owner key already
    // matched and no switch happened at all. Handing the answer back lets the
    // caller finish with its own context first and restart deliberately.
    return switched;
  }

  /// Clear the session, locally and on the server.
  ///
  /// The server call is what actually ends the session: it bumps the account's
  /// token version, so every token already issued stops working. Clearing only
  /// the device copy - which is all this used to do - left a 30-day credential
  /// valid for anyone who had already taken one.
  ///
  /// Best-effort, and deliberately so: a user signing out on a dead network
  /// must still get signed out on this device.
  Future<void> signOut({bool revokeRemotely = true}) async {
    if (revokeRemotely && _cfg.authToken != null) {
      try {
        await _post('/api/auth/logout', {});
      } catch (_) {
        // Nothing to do about it here; the local clear below still happens.
      }
    }
    await SessionStore.clear();
    _cfg
      ..authToken = null
      ..refreshToken = null
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

  // ── Moderation ──
  //
  // Report and block. Apple requires both of any app carrying user-generated
  // content, and this one carries a feed, comments, direct messages and live
  // voice.

  /// Flag something for review. [targetType] is post | comment | message | user
  /// | room. [snapshot] is a copy of what the reporter was looking at, because
  /// the author can delete or edit it before anyone reads the report.
  Future<void> reportContent({
    required String targetType,
    required String targetId,
    required String reason,
    String? note,
    String? snapshot,
  }) =>
      _post('/api/reports', {
        'targetType': targetType,
        'targetId': targetId,
        'reason': reason,
        if (note != null && note.isNotEmpty) 'note': note,
        if (snapshot != null && snapshot.isNotEmpty) 'snapshot': snapshot,
      });

  Future<void> blockUser(String userId) => _post('/api/blocks', {'userId': userId});

  Future<void> unblockUser(String userId) => delete('/api/blocks/$userId');

  /// The people this user has blocked, newest first.
  Future<List<BlockedUser>> fetchBlocked() async {
    final j = await _get('/api/blocks');
    return (j['blocked'] as List)
        .map((b) => BlockedUser.fromJson((b as Map).cast()))
        .toList();
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

  // ── Coach entitlement ──
  /// Where this account stands today, without spending a turn.
  Future<Map<String, dynamic>> coachQuota() =>
      _get('/api/coach/quota?tz=${Uri.encodeComponent(DateTime.now().timeZoneName)}');

  /// Claim one coaching turn. Throws [CoachTurnRefused] when today's free-tier
  /// budget is spent.
  ///
  /// The coach reply itself is generated on the device by Puter, so this is the
  /// only point at which the server can enforce the cap - which is exactly why
  /// it exists rather than the count being kept locally.
  Future<({bool premium, int? remaining})> spendCoachTurn() async {
    try {
      final j = await _post('/api/coach/turn', {});
      return (premium: j['premium'] == true, remaining: j['remaining'] as int?);
    } on ApiException catch (e) {
      if (e.statusCode == 402) throw const CoachTurnRefused();
      rethrow;
    }
  }

  // ── Account: erasure and portability ──
  /// Permanently delete this account. [confirm] must equal the user's own
  /// display name; the server rejects anything else, so this cannot be reached
  /// by a mis-tap.
  Future<void> deleteAccount({required String confirm}) async {
    await delete('/api/me', {'confirm': confirm});
    await signOut(revokeRemotely: false); // the account is gone; nothing to revoke
  }

  /// Everything stored about this account, as one JSON document.
  Future<Map<String, dynamic>> exportMyData() => _get('/api/me/export');

  // ── Health-data consent ──
  /// The account's current answer, and whether it needs asking again because
  /// the policy has moved on since it was given.
  Future<Map<String, dynamic>> fetchHealthConsent() => _get('/api/consent/health');

  /// Record a decision. [source] is 'onboarding' or 'settings'; the policy
  /// version is the server's, not ours, so the app cannot claim someone agreed
  /// to wording that was never on their screen.
  Future<Map<String, dynamic>> setHealthConsent({
    required bool granted,
    required String source,
  }) =>
      _post('/api/consent/health', {'granted': granted, 'source': source});

  /// Erase the health-related documents already stored for this account.
  /// Returns how many were removed.
  Future<int> deleteHealthData() async {
    final j = await delete('/api/consent/health/data');
    return j['deletedDocuments'] as int? ?? 0;
  }

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

/// Today's free coaching turns are spent. The UI answers this with the
/// paywall; anything else would be a silent failure on a feature the user is
/// entitled to be told about.
class CoachTurnRefused implements Exception {
  const CoachTurnRefused();
  @override
  String toString() => 'CoachTurnRefused';
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;
  @override
  String toString() => 'ApiException($message)';
}
