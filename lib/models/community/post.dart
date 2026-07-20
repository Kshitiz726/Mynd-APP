import '../energy_level.dart';

/// The three stateful reactions in the feed UI, bound to their Lucide icons.
/// Mirrors the server's `reaction_kind` enum and `_PostCard.reacts` shapes.
enum ReactionKind {
  relate(iconName: 'heart', label: 'relate'),
  support(iconName: 'hug', label: 'support'),
  proud(iconName: 'clap', label: 'proud');

  const ReactionKind({required this.iconName, required this.label});
  final String iconName;
  final String label;

  static ReactionKind fromName(String s) =>
      ReactionKind.values.firstWhere((r) => r.name == s);
}

/// A community feed post. Counts come pre-aggregated from the server (the
/// `posts.*_count` trigger columns), and [myReactions] tells the UI which
/// react buttons render in the active state.
class Post {
  Post({
    required this.id,
    required this.authorName,
    required this.initial,
    required this.avatarColor,
    required this.avatarTextColor,
    required this.body,
    required this.mood,
    required this.tags,
    required this.createdAt,
    required this.commentCount,
    required this.counts,
    required this.myReactions,
  });

  final String id;
  final String authorName;
  final String initial;
  final String avatarColor;     // hex string, e.g. '#E0E7FF'
  final String avatarTextColor;
  final String body;
  final EnergyLevel? mood;      // the "Low Energy" / "Energized" pill
  final List<String> tags;      // ['Study', 'Struggles'] - render with '#'
  final DateTime createdAt;
  final int commentCount;

  /// Live counts per reaction kind.
  final Map<ReactionKind, int> counts;

  /// Which reactions the current user already holds (drives `active` styling).
  final Set<ReactionKind> myReactions;

  int countOf(ReactionKind k) => counts[k] ?? 0;
  bool isActive(ReactionKind k) => myReactions.contains(k);

  factory Post.fromJson(Map<String, dynamic> j) {
    EnergyLevel? mood;
    if (j['mood'] != null) {
      mood = EnergyLevel.values.firstWhere(
        (e) => e.name == j['mood'] || (j['mood'] == 'dead' && e == EnergyLevel.dead),
        orElse: () => EnergyLevel.low,
      );
    }
    final mine = ((j['my_reactions'] as List?) ?? const [])
        .map((s) => ReactionKind.fromName(s as String))
        .toSet();
    return Post(
      id: j['id'] as String,
      authorName: j['display_name'] as String? ?? 'Someone',
      initial: j['initial'] as String? ?? '?',
      avatarColor: j['avatar_color'] as String? ?? '#E0E7FF',
      avatarTextColor: j['avatar_text_color'] as String? ?? '#4F46E5',
      body: j['body'] as String,
      mood: mood,
      tags: ((j['tags'] as List?) ?? const []).cast<String>(),
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      commentCount: (j['comment_count'] as int?) ?? 0,
      counts: {
        ReactionKind.relate: (j['relate_count'] as int?) ?? 0,
        ReactionKind.support: (j['support_count'] as int?) ?? 0,
        ReactionKind.proud: (j['proud_count'] as int?) ?? 0,
      },
      myReactions: mine,
    );
  }

  /// Returns a copy with one reaction toggled to [active] and counts replaced
  /// by the server-authoritative values from a `reaction_update` event.
  Post applyReaction(ReactionKind kind, bool active, Map<ReactionKind, int> newCounts) {
    final mine = {...myReactions};
    active ? mine.add(kind) : mine.remove(kind);
    return Post(
      id: id, authorName: authorName, initial: initial, avatarColor: avatarColor,
      avatarTextColor: avatarTextColor, body: body, mood: mood, tags: tags,
      createdAt: createdAt, commentCount: commentCount,
      counts: {...counts, ...newCounts}, myReactions: mine,
    );
  }
}

class PostComment {
  PostComment({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.initial,
    required this.avatarColor,
    required this.body,
    required this.createdAt,
    this.parentId,
    this.path,
    this.upvoteCount = 0,
    this.hasUpvoted = false,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String initial;
  final String avatarColor;
  final String body;
  final DateTime createdAt;
  final String? parentId;
  final String? path;
  final int upvoteCount;
  final bool hasUpvoted;

  factory PostComment.fromJson(Map<String, dynamic> j) {
    return PostComment(
      id: j['id'] as String,
      authorId: j['author_id'] as String,
      authorName: j['display_name'] as String? ?? 'Someone',
      initial: j['initial'] as String? ?? '?',
      avatarColor: j['avatar_color'] as String? ?? '#E0E7FF',
      body: j['body'] as String,
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? DateTime.now(),
      parentId: j['parent_id'] as String?,
      path: j['path'] as String?,
      upvoteCount: int.tryParse(j['upvote_count']?.toString() ?? '0') ?? 0,
      hasUpvoted: j['has_upvoted'] == true,
    );
  }

  PostComment copyWith({
    int? upvoteCount,
    bool? hasUpvoted,
  }) {
    return PostComment(
      id: id,
      authorId: authorId,
      authorName: authorName,
      initial: initial,
      avatarColor: avatarColor,
      body: body,
      createdAt: createdAt,
      parentId: parentId,
      path: path,
      upvoteCount: upvoteCount ?? this.upvoteCount,
      hasUpvoted: hasUpvoted ?? this.hasUpvoted,
    );
  }
}
