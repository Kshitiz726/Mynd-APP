import 'feed_post.dart';

/// One story in the Feed.
///
/// Only what a publisher puts in their own metadata: a headline, the summary
/// they wrote for it, their image and their name. The article body is theirs
/// and is never carried here - tapping a card opens the source.
class NewsItem {
  const NewsItem({
    required this.title,
    required this.url,
    this.summary,
    this.imageUrl,
    this.source,
    this.publishedAt,
  });

  final String title;
  final String url;
  final String? summary;
  final String? imageUrl;
  final String? source;
  final DateTime? publishedAt;

  /// Null rather than throwing on a malformed row: one bad item in a feed of
  /// twelve should cost that item, not the screen.
  static NewsItem? fromJson(Map<String, dynamic> j) {
    final title = (j['title'] as String?) == null
        ? null
        : FeedPost.stripMarkup(j['title'] as String);
    final url = (j['url'] as String?)?.trim();
    if (title == null || title.isEmpty || url == null || url.isEmpty) {
      return null;
    }
    final raw = j['publishedAt'] as String?;
    return NewsItem(
      title: title,
      url: url,
      // Stripped here too, so markup never reaches the prompt. A model shown
      // an anchor tag in the source summary will cheerfully carry it into the
      // post it writes, and then the card has markup that no server fix
      // touches because the server never saw that sentence.
      summary: (j['summary'] as String?) == null
          ? null
          : FeedPost.stripMarkup(j['summary'] as String),
      imageUrl: (j['imageUrl'] as String?)?.trim(),
      source: (j['source'] as String?)?.trim(),
      publishedAt: raw == null ? null : DateTime.tryParse(raw),
    );
  }

  /// "2h ago", "yesterday". Absolute dates mean nothing on a feed you glance
  /// at; how fresh it is, is the whole question.
  String get age {
    final at = publishedAt;
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '';
  }
}
