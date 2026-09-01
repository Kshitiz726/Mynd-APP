import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/local_news.dart';

void main() {
  // The first two <title>s in a Google News feed belong to the channel, not to
  // any story. Taking them would put "Bristol - Google News" in front of
  // somebody as if it were the news.
  test('channel titles are not headlines', () {
    const xml = '''
<rss><channel>
  <title>"Bristol" - Google News</title>
  <item><title>Harbour festival returns - BBC</title></item>
  <item><title>New bus route opens - Post</title></item>
</channel></rss>''';
    expect(LocalNews.titles(xml), [
      'Harbour festival returns - BBC',
      'New bus route opens - Post',
    ]);
  });

  test('entities come back as the characters they stand for', () {
    const xml = '<item><title>Bath &amp; Wells say &quot;yes&quot;</title></item>';
    expect(LocalNews.titles(xml), ['Bath & Wells say "yes"']);
  });

  // &amp;quot; is an escaped ampersand followed by the letters "quot;", not a
  // quote mark. Unescaping ampersands first would turn it into one, so a
  // headline about HTML would come back mangled.
  test('an escaped entity is not unescaped twice', () {
    const xml = '<item><title>Type &amp;quot; for a quote</title></item>';
    expect(LocalNews.titles(xml), ['Type &quot; for a quote']);
  });

  test('numeric entities and CDATA are handled', () {
    const xml = '<item><title><![CDATA[Caf&#233; reopens]]></title></item>';
    expect(LocalNews.titles(xml), ['Café reopens']);
  });

  test('the limit is respected', () {
    final xml = List.generate(10, (i) => '<item><title>story $i</title></item>').join();
    expect(LocalNews.titles(xml, limit: 3).length, 3);
  });

  test('a document with nothing in it is empty, not an error', () {
    expect(LocalNews.titles('<rss><channel></channel></rss>'), isEmpty);
    expect(LocalNews.titles(''), isEmpty);
  });
}
