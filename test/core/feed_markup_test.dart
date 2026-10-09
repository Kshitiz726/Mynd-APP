import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/models/feed_post.dart';
import 'package:ourmynd/models/news_item.dart';

/// Raw `<a href=...>` was showing on feed cards. The cause was an ordering
/// mistake: tags were stripped first and entities decoded afterwards, so for
/// every feed that escapes its description - Google News does - the decode
/// step CREATED the markup after the only pass that would have removed it.
void main() {
  group('stripMarkup', () {
    test('an escaped anchor is removed, not decoded into one', () {
      expect(
        FeedPost.stripMarkup(
            '&lt;a href="https://x.com/y"&gt;Council approves bridge&lt;/a&gt;'),
        'Council approves bridge',
      );
    });

    test('a literal anchor is removed too', () {
      expect(FeedPost.stripMarkup('<a href="https://x.com">Headline</a> and more'),
          'Headline and more');
    });

    test('double encoding needs the second pass', () {
      // Feeds that escape an already-escaped description. One pass turns this
      // into &lt;a&gt; and stops; two turns it into a tag and removes it.
      expect(
        FeedPost.stripMarkup('&amp;lt;a href=&amp;quot;u&amp;quot;&amp;gt;Double&amp;lt;/a&amp;gt;'),
        'Double',
      );
    });

    test('an ampersand in ordinary prose survives', () {
      expect(FeedPost.stripMarkup('Marks &amp; Spencer reports growth'),
          'Marks & Spencer reports growth');
    });

    test('entities that are text become text', () {
      expect(FeedPost.stripMarkup('Caf&#233; opens &#x27;early&#x27;'),
          "Café opens 'early'");
    });

    test('a stray angle bracket cannot start a tag', () {
      expect(FeedPost.stripMarkup('5 < 6 and 7 > 6'), contains('5'));
      expect(FeedPost.stripMarkup('5 < 6 and 7 > 6'), isNot(contains('<')));
    });
  });

  test('a post read back from storage is cleaned', () {
    // The editions already written to the device hold what the old server
    // sent, so the fix has to apply on the way out of storage as well.
    final post = FeedPost.fromJson({
      'id': 'p1',
      'title': '&lt;b&gt;Bridge approved&lt;/b&gt;',
      'body': 'Full story &lt;a href="https://x.com"&gt;here&lt;/a&gt;.',
    });

    expect(post, isNotNull);
    expect(post!.title, 'Bridge approved');
    expect(post.body, isNot(contains('href')));
    expect(post.body, isNot(contains('<')));
  });

  test('an article summary is cleaned before it can reach the prompt', () {
    // A model shown an anchor tag will carry it into the post it writes, and
    // no server fix touches a sentence the server never saw.
    final item = NewsItem.fromJson({
      'title': '&lt;i&gt;Quiet news day&lt;/i&gt;',
      'url': 'https://example.com/a',
      'summary': 'Read it &lt;a href="https://example.com/a"&gt;at the source&lt;/a&gt;',
    });

    expect(item, isNotNull);
    expect(item!.title, 'Quiet news day');
    expect(item.summary, isNot(contains('href')));
  });
}
