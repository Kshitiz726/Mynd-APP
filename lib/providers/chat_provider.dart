import 'dart:async';

import 'package:flutter/foundation.dart'; // Uint8List, ChangeNotifier, debugPrint

import '../core/services/api_client.dart';
import '../core/services/api_config.dart';
import '../core/services/realtime_service.dart';
import '../models/community/chat_models.dart';

/// Drives the Groups lists (suggested + joined), the Chats list, and the
/// currently-open conversation. Messages stream live over `message_new`; sends
/// are optimistic and reconciled by `clientTempId`; history is served instantly
/// from an in-memory cache while a fresh fetch reconciles in the background.
class ChatProvider extends ChangeNotifier {
  ChatProvider() {
    _rt.addReconnectListener(_onReconnect);
  }

  final _api = ApiClient.instance;
  final _rt = RealtimeService.instance;

  // ── Groups ──
  List<Group> suggestedGroups = [];
  List<Group> myGroups = [];
  bool loadingGroups = false;

  // ── Conversations ──
  List<ChatConversation> conversations = [];
  bool loadingConvos = false;

  // ── Active conversation ──
  String? activeConversationId;
  String? activeChatTitle;
  String? activeChatIconName;
  String? activeChatIconColor;
  bool activeChatIsGroup = false;

  ChatMsg? replyingTo;

  List<ChatMsg> messages = [];

  // Per-conversation message cache → instant render on (re)entry.
  static final Map<String, List<ChatMsg>> _cache = {};

  // Remote typing state: userId → display name, each with an expiry timer.
  final Map<String, String> _typing = {};
  final Map<String, Timer> _typingExpiry = {};
  Timer? _localTypingStop;
  bool _localTyping = false;

  bool _wired = false;

  // ───────────────────────────── Groups ─────────────────────────────

  Future<void> loadGroups() async {
    loadingGroups = true;
    notifyListeners();
    try {
      final results = await Future.wait([_api.fetchSuggestedGroups(limit: 5), _api.fetchMyGroups()]);
      suggestedGroups = results[0];
      myGroups = results[1];
    } catch (e) {
      debugPrint('loadGroups failed: $e');
    }
    loadingGroups = false;
    notifyListeners();
  }

  /// Tap "Join" on a suggested group: the row leaves "Groups for you" and lands
  /// in "Your groups" instantly; the network call backfills the conversation id
  /// and a replacement suggestion. Reverts on failure.
  Future<void> joinGroup(Group g) async {
    final prevSuggested = suggestedGroups;
    final prevMine = myGroups;

    suggestedGroups = suggestedGroups.where((x) => x.id != g.id).toList();
    myGroups = [g.copyWith(joined: true, memberCount: g.memberCount + 1), ...myGroups];
    notifyListeners();

    try {
      final cid = await _api.joinGroup(g.id);
      myGroups = [
        for (final m in myGroups)
          if (m.id == g.id) m.copyWith(conversationId: cid) else m,
      ];
      notifyListeners();
      // Keep the rail at 5 — pull a fresh suggestion in the background.
      _api.fetchSuggestedGroups(limit: 5).then((s) {
        suggestedGroups = s.where((x) => myGroups.every((m) => m.id != x.id)).toList();
        notifyListeners();
      }).catchError((_) {});
    } catch (e) {
      debugPrint('joinGroup failed: $e');
      suggestedGroups = prevSuggested;
      myGroups = prevMine;
      notifyListeners();
      rethrow;
    }
  }

  /// Resolve a group's conversation id, awaiting the cached one if present.
  Future<String> conversationForGroup(Group g) async =>
      g.conversationId ?? await _api.openGroupChat(g.id);

  // ───────────────────────────── Conversations ─────────────────────────────

  Future<void> loadConversations() async {
    loadingConvos = true;
    notifyListeners();
    try {
      conversations = await _api.fetchConversations();
    } catch (e) {
      debugPrint('loadConversations failed: $e');
    }
    loadingConvos = false;
    notifyListeners();
  }

  Future<String> openDirect(String userId) => _api.openDirect(userId);

  // ───────────────────────────── Active chat ─────────────────────────────

  /// Opens a chat, setting the UI metadata and subscribing to live messages.
  Future<void> openChat({
    required String id,
    required String title,
    String? iconName,
    String? iconColor,
    bool isGroup = false,
  }) async {
    activeChatTitle = title;
    activeChatIconName = iconName;
    activeChatIconColor = iconColor;
    activeChatIsGroup = isGroup;
    await enterConversation(id);
  }

  /// Wire the realtime chat listeners app-wide and load the conversation list.
  /// Called once from the shell after sign-in so messages land in the Chats list
  /// instantly (Instagram-style) even when no chat is open. Safe to call twice.
  Future<void> initRealtime() async {
    await _wire();
    loadConversations();
  }

  Future<void> enterConversation(String id) async {
    activeConversationId = id;
    messages = _cache[id] ?? [];
    // Opening a chat clears its unread badge in the list immediately.
    conversations = [
      for (final c in conversations) c.id == id ? c.copyWith(unread: 0) : c,
    ];
    _clearTyping();
    notifyListeners();

    await _wire();

    // Subscribe first so nothing sent between fetch and subscribe is missed.
    final ack = await _rt.openConversation(id);
    if (ack['ok'] != true) {
      debugPrint('open_conversation rejected: ${ack['error']}');
    }

    _fetchAndMerge(id);
  }

  Future<void> _fetchAndMerge(String id) async {
    try {
      final fresh = await _api.fetchMessages(id);
      if (activeConversationId != id) return; // Left chat while fetching
      // Merge: server history + any optimistic-in-flight bubbles not yet acked.
      final pending = messages.where((m) => m.status == SendStatus.sending || m.status == SendStatus.failed);
      messages = _dedup([...fresh, ...pending]);
      _cache[id] = messages;
      notifyListeners();
    } catch (e) {
      debugPrint('fetchMessages failed: $e');
    }
    _api.markRead(id).catchError((_) {});
  }

  void exitConversation() {
    final id = activeConversationId;
    if (id != null) _cache[id] = messages;
    activeConversationId = null;
    messages = [];
    replyingTo = null;
    _stopLocalTyping();
    _clearTyping();
    notifyListeners();
  }

  void setReplyingTo(ChatMsg? msg) {
    replyingTo = msg;
    notifyListeners();
  }

  // ── Sending ──

  void sendText(String body) {
    final id = activeConversationId;
    final text = body.trim();
    if (id == null || text.isEmpty) return;
    _stopLocalTyping();
    final tempId = _tempId();
    
    final replyId = replyingTo?.id;
    final replyBody = replyingTo?.body;
    final replySender = replyingTo?.senderName;
    
    _appendLocal(ChatMsg.local(
      id, tempId, 
      body: text,
      replyToId: replyId,
      replyToBody: replyBody,
      replyToSender: replySender,
    ));
    _dispatch(id, tempId, body: text, replyToId: replyId);
    
    replyingTo = null;
    notifyListeners();
  }

  void retry(ChatMsg msg) {
    final id = activeConversationId;
    if (id == null || msg.clientTempId == null) return;
    _patchLocal(msg.clientTempId!, (m) => m.copyWith(status: SendStatus.sending));
    _dispatch(id, msg.clientTempId!, body: msg.body, replyToId: msg.replyToId);
  }

  Future<void> _dispatch(String conversationId, String tempId, {String body = '', String? replyToId}) async {
    debugPrint('[chat] sending tempId=$tempId convo=$conversationId replyToId=$replyToId');
    final ack = await _rt.sendMessage(conversationId, tempId, body: body, replyToId: replyToId);
    debugPrint('[chat] send ack ok=${ack['ok']} err=${ack['error']}');
    if (ack['ok'] == true && ack['message'] is Map) {
      // Reconcile straight from the ack — "sent" no longer depends on the
      // broadcast round-trip arriving (message_new still dedups if it does).
      _reconcile(tempId, ChatMsg.fromJson((ack['message'] as Map).cast()));
    } else if (ack['ok'] != true) {
      _patchLocal(tempId, (m) => m.copyWith(status: SendStatus.failed));
    }
  }

  /// Replace an optimistic bubble (by temp id) with the authoritative server row.
  void _reconcile(String tempId, ChatMsg server) {
    final i = messages.indexWhere((m) => m.clientTempId == tempId || m.id == tempId);
    if (i >= 0) {
      messages = [...messages]..[i] = server;
    } else if (!messages.any((m) => m.id == server.id)) {
      messages = [...messages, server];
    }
    final id = activeConversationId;
    if (id != null) _cache[id] = messages;
    notifyListeners();
  }

  // ── Typing ──

  String? get typingLabel {
    if (_typing.isEmpty) return null;
    final names = _typing.values.toList();
    if (names.length == 1) return '${names.first} is typing…';
    if (names.length == 2) return '${names[0]} and ${names[1]} are typing…';
    if (names.length == 3) return '${names[0]}, ${names[1]}, and ${names[2]} are typing…';
    return 'Several people are typing…';
  }

  /// Call on every composer change. Debounced: emits typing(true) once, then
  /// typing(false) after 2.5s of no input.
  void onComposerChanged(String text) {
    final id = activeConversationId;
    if (id == null) return;
    if (text.trim().isEmpty) {
      _stopLocalTyping();
      return;
    }
    if (!_localTyping) {
      _localTyping = true;
      _rt.typing(id, true);
    }
    _localTypingStop?.cancel();
    _localTypingStop = Timer(const Duration(milliseconds: 2500), _stopLocalTyping);
  }

  void _stopLocalTyping() {
    _localTypingStop?.cancel();
    _localTypingStop = null;
    if (_localTyping) {
      _localTyping = false;
      final id = activeConversationId;
      if (id != null) _rt.typing(id, false);
    }
  }

  // ───────────────────────────── Internals ─────────────────────────────

  Future<void> _wire() async {
    if (_wired) return;
    _wired = true;
    await _rt.ensureConnected();

    _rt.on('message_new', (d) {
      final cid = d['conversationId'] as String?;
      if (cid == null) return;
      final msg = ChatMsg.fromJson((d['message'] as Map).cast());

      // Always keep the Chats list fresh (preview + unread + ordering), whether
      // or not this conversation is currently open.
      _bumpConversation(cid, msg);

      // Only the open conversation appends to the live message thread.
      if (cid != activeConversationId) {
        notifyListeners();
        return;
      }
      final tempId = d['clientTempId'] as String?;
      final i = tempId != null ? messages.indexWhere((m) => m.clientTempId == tempId || m.id == tempId) : -1;
      if (i >= 0) {
        final copy = [...messages]..[i] = msg;
        messages = copy;
      } else if (!messages.any((m) => m.id == msg.id)) {
        messages = [...messages, msg];
      }
      _cache[cid] = messages;
      // A new inbound message clears that sender's typing bubble.
      _expireTyping(msg.senderId);
      notifyListeners();
    });

    _rt.on('typing', (d) {
      if (d['conversationId'] != activeConversationId) return;
      final uid = d['userId'] as String?;
      if (uid == null || uid == ApiConfig.instance.userId) return;
      if (d['isTyping'] == true) {
        _typing[uid] = (d['name'] ?? 'Someone') as String;
        _typingExpiry[uid]?.cancel();
        // Self-heal if a stop event is ever lost.
        _typingExpiry[uid] = Timer(const Duration(seconds: 5), () => _expireTyping(uid));
      } else {
        _expireTyping(uid);
      }
      notifyListeners();
    });
  }

  void _onReconnect() {
    final id = activeConversationId;
    if (id != null) _rt.openConversation(id);
  }

  /// Update the Chats list when a message arrives: refresh the preview, bump
  /// unread (unless it's mine or the open chat), and move the row to the top.
  void _bumpConversation(String cid, ChatMsg msg) {
    final preview = switch (msg.kind) {
      MsgKind.image => '📷 Photo',
      MsgKind.file => '📎 File',
      MsgKind.text => msg.body,
    };
    final idx = conversations.indexWhere((c) => c.id == cid);
    if (idx < 0) {
      // A conversation we don't know about yet (e.g. a brand-new DM) — pull a
      // fresh list so it shows up.
      loadConversations();
      return;
    }
    final countsUnread = cid != activeConversationId && !msg.mine;
    final updated = conversations[idx].copyWith(
      lastMessage: preview,
      unread: countsUnread ? conversations[idx].unread + 1 : conversations[idx].unread,
    );
    conversations = [updated, ...conversations.where((c) => c.id != cid)];
  }

  void _appendLocal(ChatMsg m) {
    messages = [...messages, m];
    final id = m.conversationId;
    _cache[id] = messages;
    notifyListeners();
  }

  void _patchLocal(String tempId, ChatMsg Function(ChatMsg) f) {
    final i = messages.indexWhere((m) => m.clientTempId == tempId);
    if (i < 0) return;
    messages = [...messages]..[i] = f(messages[i]);
    final id = activeConversationId;
    if (id != null) _cache[id] = messages;
    notifyListeners();
  }

  void _expireTyping(String uid) {
    _typing.remove(uid);
    _typingExpiry.remove(uid)?.cancel();
  }

  void _clearTyping() {
    _typing.clear();
    for (final t in _typingExpiry.values) {
      t.cancel();
    }
    _typingExpiry.clear();
  }

  List<ChatMsg> _dedup(List<ChatMsg> list) {
    final seen = <String>{};
    final out = <ChatMsg>[];
    for (final m in list) {
      final key = m.clientTempId ?? m.id;
      if (seen.add(key)) out.add(m);
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  String _tempId() => 'tmp_${DateTime.now().microsecondsSinceEpoch}';

  @override
  void dispose() {
    _rt.removeReconnectListener(_onReconnect);
    _localTypingStop?.cancel();
    _clearTyping();
    super.dispose();
  }
}
