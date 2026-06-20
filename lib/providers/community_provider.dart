import 'package:flutter/foundation.dart';

import '../core/services/api_client.dart';
import '../core/services/api_config.dart';
import '../core/services/realtime_service.dart';
import '../models/community/post.dart';

/// Drives the Community feed: loads posts over REST, applies live
/// `reaction_update` events over the socket, and sends optimistic reactions.
class CommunityProvider extends ChangeNotifier {
  final _api = ApiClient.instance;
  final _rt = RealtimeService.instance;

  final List<Post> _posts = [];
  List<Post> get posts => List.unmodifiable(_posts);

  bool loading = false;
  String? _cursor;
  String? activeTag; // '#Study' filter
  bool _wired = false;

  Future<void> loadFeed({String? tag, bool refresh = false}) async {
    if (refresh) {
      _posts.clear();
      _cursor = null;
    }
    activeTag = tag;
    loading = true;
    notifyListeners();

    final page = await _api.fetchFeed(cursor: _cursor, tag: tag);
    _posts.addAll(page.posts);
    _cursor = page.nextCursor;
    for (final p in page.posts) {
      _rt.watchPost(p.id); // subscribe to live reaction updates for visible posts
    }
    _wireListeners();
    loading = false;
    notifyListeners();
  }

  Future<void> createPost({required String body, String? mood, List<String> tags = const []}) async {
    final post = await _api.createPost(body: body, mood: mood, tags: tags);
    _posts.insert(0, post);
    _rt.watchPost(post.id);
    notifyListeners();
  }

  /// Optimistic toggle: flip locally now, let the server's `reaction_update`
  /// reconcile the authoritative counts a moment later.
  void toggleReaction(String postId, ReactionKind kind) {
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx < 0) return;
    final p = _posts[idx];
    final nowActive = !p.isActive(kind);
    final optimistic = {...p.counts};
    optimistic[kind] = (optimistic[kind] ?? 0) + (nowActive ? 1 : -1);
    _posts[idx] = p.applyReaction(kind, nowActive, optimistic);
    notifyListeners();

    _rt.react(postId, kind.name);
  }

  void _wireListeners() {
    if (_wired) return;
    _wired = true;
    _rt.on('reaction_update', (d) {
      final idx = _posts.indexWhere((p) => p.id == d['postId']);
      if (idx < 0) return;
      final counts = (d['counts'] as Map).cast<String, dynamic>();
      final kind = ReactionKind.fromName(d['kind'] as String);
      _posts[idx] = _posts[idx].applyReaction(
        kind,
        // only flip "mine" if I was the actor; others' reactions just change counts
        d['actorId'] == _myId ? d['active'] as bool : _posts[idx].isActive(kind),
        {
          ReactionKind.relate: counts['relate'] as int,
          ReactionKind.support: counts['support'] as int,
          ReactionKind.proud: counts['proud'] as int,
        },
      );
      notifyListeners();
    });
  }

  String? get _myId => ApiConfig.instance.userId;
}
