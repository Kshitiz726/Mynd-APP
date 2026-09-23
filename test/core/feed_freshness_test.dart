import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/models/news_item.dart';
import 'package:ourmynd/providers/feed_provider.dart';

/// The feed's one promise beyond "it is written for you": that this morning is
/// not last night. It was broken by a dedupe set that lived and died inside a
/// single write, so it could only ever stop a repeat within one edition.
void main() {
  NewsItem item(String title, String url) => NewsItem(title: title, url: url);

  test('the same article is the same story however it is fetched', () {
    // Trackers on the end of the URL are the normal case, not the exception:
    // the same article comes back with a different query string every time.
    final a = FeedProvider.seenKeysFor(
        item('Council approves the new bridge', 'https://x.com/a/bridge'));
    final b = FeedProvider.seenKeysFor(item('Council approves the new bridge',
        'https://X.com/a/bridge?utm_source=rss&id=99'));

    expect(a.first, b.first, reason: 'the query string changed the identity');
    expect(a.any(b.contains), isTrue);
  });

  test('the same story from a second publisher is still the same story', () {
    // One news event otherwise fills an edition on its own, once through each
    // outlet that carried it.
    final a = FeedProvider.seenKeysFor(
        item('Council approves the new bridge', 'https://one.com/a'));
    final b = FeedProvider.seenKeysFor(
        item('Council Approves The New Bridge!', 'https://two.com/b'));

    expect(a.first == b.first, isFalse, reason: 'different links, as expected');
    expect(a.any(b.contains), isTrue,
        reason: 'the headline should have matched the two up');
  });

  test('two genuinely different stories do not collide', () {
    final a = FeedProvider.seenKeysFor(
        item('Council approves the new bridge', 'https://one.com/a'));
    final b = FeedProvider.seenKeysFor(
        item('Council rejects the ring road plan', 'https://one.com/b'));

    expect(a.any(b.contains), isFalse);
  });

  test('a headline too short to be distinctive is not used as a key', () {
    // 'Budget day' would match every 'Budget day' ever written, and suppressing
    // a story that was never run is worse than running one twice.
    final keys = FeedProvider.seenKeysFor(item('Budget', 'https://one.com/a'));
    expect(keys.where((k) => k.startsWith('t:')), isEmpty);
    expect(keys.where((k) => k.startsWith('u:')), hasLength(1));
  });
}
