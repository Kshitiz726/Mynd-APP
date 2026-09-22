import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ourmynd/core/services/api_client.dart';
import 'package:ourmynd/core/services/feed_instructions_service.dart';
import 'package:ourmynd/core/services/session_store.dart';
import 'package:ourmynd/providers/feed_provider.dart';

/// Does the feed get pictures?
///
/// Two halves, and the second is the one that was missed. The first asks
/// whether articles come back carrying an image at all, which is live or it is
/// nothing: the picture is read off the publisher's own page at request time.
///
/// The second writes a real edition through the real provider, with the real
/// model doing the choosing, and looks at the cards that come out. That gap is
/// where the bug lived the first time round. Articles were arriving with
/// pictures and the endpoint test passed, while every card on the screen was
/// still text only, because the join between a written post and its article
/// was a URL the model had been asked to copy out by hand.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('news comes back with publisher images', (tester) async {
    expect(await SessionStore.restore(), isTrue,
        reason: 'no session on this device - sign in first');

    final items = await ApiClient.instance.fetchNews('adhd focus', limit: 6);
    debugPrint('[e2e] ${items.length} articles');
    expect(items, isNotEmpty, reason: 'the news source returned nothing');

    var withImages = 0;
    for (final n in items) {
      final img = n.imageUrl;
      debugPrint('[e2e] ${n.source ?? '?'} | ${n.title.substring(0, n.title.length.clamp(0, 60))}');
      debugPrint('[e2e]    image: ${img ?? 'NONE'}');
      if (img != null && img.isNotEmpty) withImages++;
      // A card links out, always. A post with no link is one nobody can check.
      expect(n.url, isNotEmpty);
    }

    debugPrint('[e2e] IMAGES: $withImages of ${items.length}');
    expect(withImages, greaterThan(0),
        reason: 'not one article carried a picture - the feed is text-only '
            'again and the source change did nothing');
  }, timeout: const Timeout(Duration(minutes: 3)));

  testWidgets('a written edition comes out with pictures on its cards',
      (tester) async {
    expect(await SessionStore.restore(), isTrue,
        reason: 'no session on this device - sign in first');
    await FeedInstructionsService.instance.init();

    final feed = FeedProvider();
    await feed.refresh();

    expect(feed.problem, isNull,
        reason: 'the feed could not be written: ${feed.problem}');
    expect(feed.editions, isNotEmpty,
        reason: 'no edition was written at all');

    final posts = feed.editions.first.posts;
    debugPrint('[e2e] edition "${feed.editions.first.label}", '
        '${posts.length} cards');

    var withImages = 0;
    for (final p in posts) {
      debugPrint('[e2e] ${p.emoji} ${p.title}');
      debugPrint('[e2e]    source: ${p.source ?? 'NONE'}');
      debugPrint('[e2e]    link:   ${p.linkUrl ?? 'NONE'}');
      debugPrint('[e2e]    image:  ${p.imageUrl ?? 'NONE'}');
      if ((p.imageUrl ?? '').isNotEmpty) withImages++;

      // Every card credits and links its source. This is what dropping an
      // unmatched post buys, and it is worth asserting rather than assuming.
      expect(p.linkUrl, isNotNull,
          reason: 'a card was published with no link to the reporting');
      expect(p.linkUrl, startsWith('http'));
      // The field name the writer sometimes leaves behind.
      expect(p.body, isNot(contains('linkText:')));
    }

    debugPrint('[e2e] CARDS WITH PICTURES: $withImages of ${posts.length}');
    expect(withImages, greaterThan(0),
        reason: 'the edition was written and not one card carried a picture, '
            'which is exactly the state this was meant to fix');
  }, timeout: const Timeout(Duration(minutes: 4)));
}
