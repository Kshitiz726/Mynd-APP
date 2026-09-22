/// One item in the Feed, and the edition it was published in.
///
/// A post is written for one person: it is the coach reading the day's sources
/// through that person's feed instructions and saying what is worth knowing.
/// So it carries prose rather than a headline and a thumbnail, and it always
/// carries the link it was built from, because the writing is a summary of
/// somebody else's reporting and the reader is owed the source.
library;

/// The tinted block under a post: the one number the post is about.
///
/// Optional, and deliberately so. A post that invents a figure to have
/// something to put in a box is worse than a post without a box.
class FeedHighlight {
  const FeedHighlight({required this.label, required this.value, this.caption});

  final String label;
  final String value;
  final String? caption;

  static FeedHighlight? fromJson(Map<String, dynamic> j) {
    final label = (j['label'] as String?)?.trim();
    final value = (j['value'] as String?)?.trim();
    if (label == null || label.isEmpty || value == null || value.isEmpty) {
      return null;
    }
    return FeedHighlight(
      label: label,
      value: value,
      caption: (j['caption'] as String?)?.trim(),
    );
  }

  Map<String, dynamic> toJson() => {
        'label': label,
        'value': value,
        if (caption != null) 'caption': caption,
      };
}

class FeedPost {
  FeedPost({
    required this.id,
    required this.emoji,
    required this.title,
    required this.body,
    this.linkText,
    this.linkUrl,
    this.source,
    this.imageUrl,
    this.highlight,
    this.liked = false,
  });

  final String id;

  /// A single glyph that says what kind of thing this is at a glance. The
  /// reference uses a graduation cap for a course, and that is the whole idea:
  /// it is a category marker, not decoration.
  final String emoji;

  final String title;

  /// The prose. [linkText] appears inside it verbatim, so the link can be
  /// rendered inline where the writing actually refers to the source.
  final String body;

  final String? linkText;
  final String? linkUrl;
  final String? source;

  /// The publisher's own picture, when the source gave one.
  ///
  /// Never asked of the model, and never matched on a URL the model echoed
  /// back. The writer names the article by a short id and the picture, the
  /// link and the publisher are all read from our own copy of that article, so
  /// a card can only ever carry the picture belonging to the story it was
  /// written from.
  final String? imageUrl;

  final FeedHighlight? highlight;

  /// Local only, and on purpose. Nothing about what somebody reads leaves the
  /// phone: a like here marks the post for them, it does not tell a server.
  bool liked;

  /// Strip a field name the writer sometimes leaves in the prose.
  ///
  /// Asked for a body and a separate linkText, a model will now and then end
  /// the body with `linkText: "the phrase"` as though it were still filling in
  /// the form. It is a small thing that makes a written card look generated,
  /// and cleaning it here rather than at the point of writing means editions
  /// already stored on the device are repaired the next time they are read.
  static String? _cleanBody(String? raw) {
    if (raw == null) return null;
    final out = raw
        .replaceAll(
            RegExp(r'\s*\b(linkText|linkUrl|ref|source)\s*:\s*"[^"]*"\s*$'), '')
        .trim();
    return out.isEmpty ? null : out;
  }

  static FeedPost? fromJson(Map<String, dynamic> j) {
    final title = (j['title'] as String?)?.trim();
    final body = _cleanBody(j['body'] as String?);
    if (title == null || title.isEmpty || body == null || body.isEmpty) {
      return null;
    }
    final h = j['highlight'];
    return FeedPost(
      id: (j['id'] as String?) ??
          'p-${DateTime.now().microsecondsSinceEpoch}-${title.hashCode}',
      emoji: (j['emoji'] as String?)?.trim().isNotEmpty == true
          ? (j['emoji'] as String).trim()
          : '📰',
      title: title,
      body: body,
      linkText: (j['linkText'] as String?)?.trim(),
      linkUrl: (j['linkUrl'] as String?)?.trim(),
      source: (j['source'] as String?)?.trim(),
      imageUrl: (j['imageUrl'] as String?)?.trim(),
      highlight: h is Map ? FeedHighlight.fromJson(h.cast<String, dynamic>()) : null,
      liked: j['liked'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'emoji': emoji,
        'title': title,
        'body': body,
        if (linkText != null) 'linkText': linkText,
        if (linkUrl != null) 'linkUrl': linkUrl,
        if (source != null) 'source': source,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (highlight != null) 'highlight': highlight!.toJson(),
        'liked': liked,
      };
}

/// A day-part's worth of posts: "Monday morning", "Monday afternoon".
///
/// Editions rather than one endless list because the feed is written, not
/// streamed. Each one is a batch the coach sat down and wrote, and labelling
/// them that way is what lets somebody scroll back through last week and see
/// where they were, rather than an undifferentiated wall.
class FeedEdition {
  const FeedEdition({
    required this.slot,
    required this.label,
    required this.at,
    required this.posts,
  });

  /// `2026-09-21:afternoon`. The identity of the edition, and what stops the
  /// app writing a second one for a day-part it has already published.
  final String slot;

  /// "Monday afternoon".
  final String label;

  final DateTime at;
  final List<FeedPost> posts;

  static FeedEdition? fromJson(Map<String, dynamic> j) {
    final slot = (j['slot'] as String?)?.trim();
    final label = (j['label'] as String?)?.trim();
    final at = DateTime.tryParse((j['at'] as String?) ?? '');
    if (slot == null || slot.isEmpty || label == null || at == null) return null;
    final posts = ((j['posts'] as List?) ?? const [])
        .whereType<Map>()
        .map((m) => FeedPost.fromJson(m.cast<String, dynamic>()))
        .whereType<FeedPost>()
        .toList();
    if (posts.isEmpty) return null;
    return FeedEdition(slot: slot, label: label, at: at, posts: posts);
  }

  Map<String, dynamic> toJson() => {
        'slot': slot,
        'label': label,
        'at': at.toIso8601String(),
        'posts': posts.map((p) => p.toJson()).toList(),
      };

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  /// Four editions a day at most. Anything finer would mean the coach writing
  /// to nobody: a feed nobody opened at 11am does not need a second one at
  /// noon, it needs the one from the morning to still be there.
  static String partOf(DateTime t) {
    final h = t.hour;
    if (h < 12) return 'morning';
    if (h < 17) return 'afternoon';
    if (h < 21) return 'evening';
    return 'night';
  }

  static String slotFor(DateTime t) {
    final d = '${t.year}-${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';
    return '$d:${partOf(t)}';
  }

  static String labelFor(DateTime t) =>
      '${_days[t.weekday - 1]} ${partOf(t)}';
}
