import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/models/feed_post.dart';
import 'package:ourmynd/models/news_item.dart';
import 'package:ourmynd/providers/feed_provider.dart';

/// Linking a written post back to the article it came from.
///
/// This is the join that decides whether a card has a picture and whether its
/// "read the original" button opens anything. It used to be done by asking the
/// model to copy a two hundred character redirect URL back verbatim, which
/// failed silently and often: the feed rendered fine, the writing was good,
/// and there was simply never an image. So the failure mode under test here is
/// not an exception, it is a null returned quietly.
void main() {
  NewsItem item(String id, {String? image}) => NewsItem(
        title: 'Article $id about attention and focus',
        url: 'https://ex.ample/$id?utm_source=rss&utm_campaign=feed&x=$id',
        source: 'Example',
        imageUrl: image,
      );

  final source = [
    item('one', image: 'https://img.ex.ample/one.jpg'),
    item('two'),
    item('three', image: 'https://img.ex.ample/three.jpg'),
  ];
  final byRef = {
    'a1': source[0],
    'a2': source[1],
    'a3': source[2],
  };

  NewsItem? match(Map<String, dynamic> m) =>
      FeedProvider.articleFor(m, byRef, source);

  test('an id finds the article, and the picture comes with it', () {
    final hit = match({'ref': 'a3', 'title': 'Something quite different'});
    expect(hit?.imageUrl, 'https://img.ex.ample/three.jpg');
    expect(hit?.url, contains('three'));
  });

  test('case and stray whitespace around the id do not lose the picture', () {
    expect(match({'ref': ' A1 '})?.imageUrl, 'https://img.ex.ample/one.jpg');
  });

  test('an article that genuinely has no picture still matches', () {
    final hit = match({'ref': 'a2'});
    expect(hit, isNotNull);
    expect(hit!.imageUrl, isNull);
  });

  test('a headline echoed instead of an id is still matched', () {
    // Some models ignore the id and hand back the article title. Cheap to
    // allow for, and it saves the card's link as well as its picture.
    final hit = match({'title': 'Article three about attention and focus'});
    expect(hit?.url, contains('three'));
  });

  test('a mangled or invented id matches nothing rather than something', () {
    // The whole point. A near miss must not resolve to a different article:
    // a real picture under the wrong headline is worse than no picture.
    for (final ref in ['a9', 'a', '', 'https://ex.ample/one', 'article 1']) {
      expect(match({'ref': ref, 'title': 'A sentence about getting started'}),
          isNull,
          reason: 'ref "$ref" should not have matched anything');
    }
  });

  test('a post with no ref and no recognisable title matches nothing', () {
    expect(match({'title': 'Why mornings are hard'}), isNull);
  });

  test('a field name left in the prose is cleaned out of the body', () {
    // Seen in a real edition on the device: the writer ended the body with
    // the linkText field as though it were still filling in the form.
    final p = FeedPost.fromJson({
      'title': 'Crypto adoption is changing shape',
      'body': 'Three trends are reshaping how people use digital assets. '
          'linkText: "crypto adoption is evolving"',
    });
    expect(p!.body, endsWith('digital assets.'));
    expect(p.body, isNot(contains('linkText')));
  });

  test('ordinary prose is left completely alone', () {
    final p = FeedPost.fromJson({
      'title': 'A morning routine that survives a bad night',
      'body': 'Researchers followed 200 people for a month. '
          'The ones who kept a fixed wake time recovered fastest.',
    });
    expect(p!.body, contains('recovered fastest.'));
  });

  test('a very short title cannot match by accident', () {
    // Substring matching on two or three characters would pair almost any
    // post with almost any article.
    expect(match({'title': 'focus'}), isNull);
  });

  group('repairing what the writer answered with', () {
    test('a raw newline inside a body no longer costs the whole edition', () {
      // Observed live: the writer laid a body out over two lines, JSON forbids
      // that inside a string, and the entire edition dropped back to bare
      // headlines because one card was formatted prettily.
      const answer = '{"posts":[{"title":"A","body":"one line\nand another"}]}';
      expect(() => jsonDecode(answer), throwsFormatException);

      final fixed = jsonDecode(FeedProvider.repairJson(answer))
          as Map<String, dynamic>;
      final post = (fixed['posts'] as List).first as Map<String, dynamic>;
      expect(post['body'], 'one line and another');
    });

    test('prose or code fences around the answer are sliced off', () {
      const answer = 'Sure, here you go:\n```json\n{"posts":[]}\n```';
      expect(jsonDecode(FeedProvider.repairJson(answer)),
          containsPair('posts', isEmpty));
    });

    test('clean json is returned untouched', () {
      const answer = '{"posts":[{"ref":"a1","title":"A","body":"B"}]}';
      expect(FeedProvider.repairJson(answer), answer);
    });
  });
}
