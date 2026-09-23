import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/api_client.dart';
import '../core/services/coach_memory_service.dart';
import '../core/services/feed_instructions_service.dart';
import '../core/services/feed_safety.dart';
import '../core/services/groq_service.dart';
import '../models/feed_post.dart';
import '../models/news_item.dart';

/// The Feed: a stack of written editions, newest first.
///
/// Not a live list of headlines. Each edition is a batch the coach wrote for
/// one person against their feed instructions, and once written it is kept on
/// the device. That is what makes the screen scrollable back through the week
/// and what makes it survive signing out and back in - the alternative, a list
/// refetched on every open, means yesterday morning is gone forever and the
/// only thing the feed can ever show you is now.
///
/// One edition per day-part, at most four a day. Opening the app twice before
/// lunch should show the same morning, not two of them.
///
/// Failure is quiet. A source, or the model, having a bad day costs an edition,
/// never the screen and never what is already stored.
class FeedProvider extends ChangeNotifier {
  static const _kEditions = 'om_feed_editions';
  static const _kSchema = 'om_feed_schema';

  /// Every story already published to this person, as key -> when.
  ///
  /// The feed used to dedupe with a set built inside one write and thrown away
  /// at the end of it, so it could only stop the same story appearing twice in
  /// the same edition. Across editions there was nothing: the queries do not
  /// change between breakfast and lunch, the news moves slower than the slots
  /// do, and so the same articles came back and were written up again. The
  /// Wednesday morning feed was Tuesday's stories, which is the one thing a
  /// feed must not be.
  static const _kSeen = 'om_feed_seen';

  /// How long a story stays "already seen". Long enough to cover the slow
  /// stories that sit near the top of a search for days, short enough that the
  /// record cannot grow without bound.
  static const _seenTtl = Duration(days: 21);

  /// Bumped when a change makes an already written edition worse than a fresh
  /// one. The current slot is then rewritten once, on the next open.
  ///
  /// Without this, somebody who had the feed open before pictures worked would
  /// keep seeing the text only edition that was already stored for this
  /// afternoon, and the fix would look like no fix at all until the day part
  /// rolled over. Older editions are left exactly as they were: they are the
  /// archive, not the front page.
  ///
  /// 3: every card carries a picture now, and stories are not repeated between
  /// editions. The edition already stored was written under neither rule, so
  /// the front page would otherwise still be the thing that was complained
  /// about.
  static const _schema = 3;

  /// Roughly a fortnight at four a day. Enough to scroll back through, small
  /// enough that the JSON stays a sane thing to keep in a preference.
  static const _maxEditions = 50;

  final List<FeedEdition> _editions = [];
  bool _loading = false;
  bool _loaded = false;
  bool _writing = false;
  String? _problem;
  bool _staleSchema = false;

  /// Keys of stories already written up, to the millisecond they were.
  final Map<String, int> _seen = {};

  List<FeedEdition> get editions => List.unmodifiable(_editions);

  /// A load is in flight. Distinct from [writing]: one is reading the disk,
  /// the other is a model composing an edition that does not exist yet.
  bool get loading => _loading;
  bool get writing => _writing;

  /// True once the stored editions have been read, however few there were.
  bool get loaded => _loaded;

  bool get isEmpty => _editions.isEmpty;

  /// Why the last attempt produced nothing, if it produced nothing.
  ///
  /// The Feed used to fail completely silently: an unreachable news source and
  /// a quiet news day both ended as "Nothing written yet", which is the one
  /// state that makes a feature look finished and broken at the same time.
  String? get problem => _problem;

  /// The instruction document the feed is written against.
  String get instructions => FeedInstructionsService.instance.text;

  /// Read what is stored, then write today's edition if it is missing.
  Future<void> load({bool force = false}) async {
    if (_loading) return;
    if (_loaded && !force) return;
    _loading = true;
    notifyListeners();

    try {
      if (!_loaded) {
        await _restore();
        await _restoreSeen();
      }
    } finally {
      _loading = false;
      _loaded = true;
      notifyListeners();
    }

    final slot = FeedEdition.slotFor(DateTime.now());
    final have = _editions.any((e) => e.slot == slot);
    final stale = _staleSchema;
    _staleSchema = false;
    debugPrint('[feed] load: slot=$slot stored=${_editions.length} '
        'have=$have force=$force stale=$stale');
    if (!have || force || stale) await _write(slot);
  }

  /// Pull to refresh: rewrite the current day-part rather than adding a
  /// second one for it.
  Future<void> refresh() => load(force: true);

  /// The instructions changed, so what is on screen is answering the old ones.
  /// Rewrite the current edition immediately rather than making somebody wait
  /// until evening to see whether their edit did anything.
  Future<void> saveInstructions(String text) async {
    await FeedInstructionsService.instance.save(text);
    notifyListeners();
    await _write(FeedEdition.slotFor(DateTime.now()));
  }

  void toggleLike(FeedPost post) {
    post.liked = !post.liked;
    notifyListeners();
    unawaited(_persist());
  }

  // ─── Writing an edition ───────────────────────────────────────────────────

  Future<void> _write(String slot) async {
    if (_writing) return;
    _writing = true;
    _problem = null;
    notifyListeners();

    try {
      final fi = FeedInstructionsService.instance;
      // Before writing, not after: an edition should reflect what has been
      // talked about since the last one, and this is the only moment the feed
      // is allowed to cost a model call for housekeeping.
      await fi.distil();

      final queries = await fi.searchQueries();
      debugPrint('[feed] queries: $queries');
      final api = ApiClient.instance;
      // Twelve per query, not six. Everything already published is now filtered
      // out, so the pool has to be deep enough that a slot can still be filled
      // from what is left after a week of filtering.
      final thisWrite = <String>{};
      final articles = <NewsItem>[];
      var fetched = 0;
      var repeats = 0;
      var blocked = 0;
      var pictureless = 0;
      for (final q in queries) {
        // A query built from an instruction asking for something this feed does
        // not carry is not run at all.
        if (isUnsafeForFeed(q, strict: true)) {
          blocked++;
          continue;
        }
        for (final n in await api.fetchNews(q, limit: 12)) {
          fetched++;

          // Never, whatever the instructions say. See feed_safety.dart.
          if (isUnsafeForFeed('${n.title} ${n.summary ?? ''}')) {
            blocked++;
            // Named, because the filter erring towards caution is the failure
            // mode worth being able to see: a headline dropped here is a real
            // story somebody will never know was withheld.
            debugPrint('[feed] blocked: ${n.title}');
            continue;
          }

          // Every card carries a real picture from its own article, so a story
          // that has none is not written up. The alternative was a feed of
          // mixed cards where the text-only ones read as broken, and the only
          // ways to fill them would be a stock photo that is not of this story
          // or a generated image, which is worse: an invented picture next to
          // a real headline is a small lie on every card.
          if (n.imageUrl == null || n.imageUrl!.isEmpty) {
            pictureless++;
            continue;
          }

          final keys = seenKeysFor(n);
          // Within this edition, and against every edition before it.
          if (keys.any(thisWrite.contains)) continue;
          if (keys.any(_seen.containsKey)) {
            repeats++;
            continue;
          }
          thisWrite.addAll(keys);
          articles.add(n);
        }
      }
      debugPrint('[feed] $fetched fetched, $repeats already published, '
          '$pictureless without a picture, $blocked blocked, '
          '${articles.length} fresh');

      if (articles.isEmpty) {
        // Several different nothings, and saying the wrong one sends somebody
        // to check their connection over a quiet news day.
        debugPrint('[feed] nothing usable for $queries');
        _problem = fetched == 0
            ? 'Could not reach the news source just now.'
            : pictureless > repeats
                ? 'Nothing with a picture came back this time. Try again in a '
                    'little while.'
                : 'Nothing new since the last edition. Everything out there '
                    'right now has already been in your feed.';
        return;
      }

      // No sort by picture any more: nothing without one gets this far.
      debugPrint('[feed] ${articles.length} articles, all with a picture');

      final posts = await _compose(articles, fi) ?? _plain(articles);
      if (posts.isEmpty) {
        _problem = 'Nothing in today\'s stories fitted your instructions.';
        return;
      }
      _problem = null;
      debugPrint('[feed] wrote ${posts.length} posts, '
          '${posts.where((p) => p.imageUrl != null).length} with a picture');

      // Recorded after composing, not before: a story that was fetched but
      // never made it into a post has not been published to anybody, and
      // burning it here would quietly shrink tomorrow's pool for nothing.
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final byUrl = {for (final a in articles) a.url: a};
      for (final post in posts) {
        final match = byUrl[post.linkUrl];
        if (match == null) continue;
        for (final k in seenKeysFor(match)) {
          _seen[k] = stamp;
        }
      }
      _pruneSeen();
      await _persistSeen();

      final now = DateTime.now();
      _editions.removeWhere((e) => e.slot == slot);
      _editions.insert(
        0,
        FeedEdition(
          slot: slot,
          label: FeedEdition.labelFor(now),
          at: now,
          posts: posts,
        ),
      );
      _editions.sort((a, b) => b.at.compareTo(a.at));
      while (_editions.length > _maxEditions) {
        _editions.removeLast();
      }
      await _persist();
    } catch (e) {
      debugPrint('[feed] could not write $slot: $e');
      _problem = 'Something went wrong writing this one.';
    } finally {
      _writing = false;
      notifyListeners();
    }
  }

  /// Ask the coach to write the edition. Null when it cannot, so the caller
  /// can fall back rather than show nothing.
  Future<List<FeedPost>?> _compose(
    List<NewsItem> articles,
    FeedInstructionsService fi,
  ) async {
    final memo = CoachMemoryService.instance.memorySummary;
    final recent = fi.recentTopics.reversed.take(8).toList();

    // Eight, trimmed. The extract route caps a message at 12k characters, and
    // a batch of long RSS descriptions is the one thing here that can reach it.
    final source = articles.take(8).toList();

    // Each article gets a short id, and the model answers with the id. It is
    // never shown a URL and never asked to reproduce one.
    //
    // This used to ask for the link back verbatim and match the picture on
    // that string, which is why the feed had no pictures: these are Bing and
    // Google redirect URLs that run to hundreds of characters, and a model
    // copying one will sooner or later drop a parameter or truncate a token.
    // A near miss cost the post its picture and left a "read the original"
    // button pointing at nothing. An id is two characters and cannot be
    // mangled into something that still looks plausible.
    final byRef = <String, NewsItem>{
      for (var i = 0; i < source.length; i++) 'a${i + 1}': source[i],
    };

    String? raw;
    try {
      final out = raw = await GroqService.instance.extract(task: 'feed', [
        {
          'role': 'system',
          'content': '''
You write a short personal feed. You are given the reader's own instructions
for what their feed covers, what they have been talking about, and today's
articles. Pick the 3 that fit the instructions best and write each one up.

For each post:
- "ref": the id of the article you wrote it from, copied exactly from the
  article's "ref" field. This is how the post is linked back to its source, so
  it must be one of the ids you were given and nothing else.
- "emoji": one emoji for the kind of thing it is.
- "title": a specific sentence, not a headline. Under 90 characters.
- "body": 2 to 4 sentences of plain prose saying what this is and what it
  means for this reader. Use the facts in the article and nothing else. Never
  invent a number, a date or a name.
- "linkText": a short phrase that appears verbatim inside "body", which will
  be turned into the link to the source.
- "highlight": optional, and only when the article states one clear figure:
  {"label":"what it is","value":"the figure","caption":"one short line"}.
  Leave it out entirely rather than inventing one.

The reader's instructions decide what is worth including. Where two articles
fit about equally well, prefer the one with "hasImage": true. If nothing fits
well, write about the closest ones honestly rather than stretching.
No outrage, no politics unless asked for, nothing designed to alarm.

Answer as JSON only: {"posts":[...]}''',
        },
        {
          'role': 'user',
          'content': jsonEncode({
            'instructions': fi.text,
            if (recent.isNotEmpty) 'recentlyTalkedAbout': recent,
            if (memo.isNotEmpty) 'aboutThisPerson': memo,
            'articles': [
              for (final e in byRef.entries)
                {
                  'ref': e.key,
                  'title': e.value.title,
                  'summary': _shorten(e.value.summary),
                  'source': e.value.source,
                  'hasImage': e.value.imageUrl != null,
                },
            ],
          }),
        },
      ]);

      final j = jsonDecode(repairJson(out)) as Map<String, dynamic>;
      final posts = <FeedPost>[];
      for (final raw in ((j['posts'] as List?) ?? const []).whereType<Map>()) {
        final m = raw.cast<String, dynamic>();
        final item = articleFor(m, byRef, source);
        // A post nothing can be matched to is dropped rather than published.
        // The writing is a summary of somebody else's reporting, so a card
        // with no source to credit and no link to open is one this app should
        // not show at all, and one fewer card is a small price.
        if (item == null) {
          debugPrint('[feed] dropped a post: no article matched '
              '(ref=${m['ref']})');
          continue;
        }
        // Link, publisher and picture all come from our own copy of the
        // article, so a card can only ever carry the picture that belongs to
        // the story it was written from.
        m['linkUrl'] = item.url;
        m['source'] = item.source;
        m['imageUrl'] = item.imageUrl;
        final p = FeedPost.fromJson(m);
        if (p != null) posts.add(p);
        if (posts.length == 4) break;
      }
      return posts.isEmpty ? null : posts;
    } catch (e) {
      // The text is logged, not just the exception. A FormatException gives a
      // character offset and nothing else, which says an edition was lost
      // without saying why, and the feed silently drops back to bare
      // headlines when this happens.
      debugPrint('[feed] could not compose: $e');
      if (raw != null) {
        debugPrint('[feed] the writer said: '
            '${raw.substring(0, raw.length.clamp(0, 400))}');
      }
      return null;
    }
  }

  /// Which article a written post came from.
  ///
  /// The id answers it in every well behaved case. The title pass is there for
  /// a model that ignored the instruction and echoed the headline instead,
  /// which costs nothing to allow for and saves the post's link and picture
  /// when it happens.
  @visibleForTesting
  static NewsItem? articleFor(
    Map<String, dynamic> m,
    Map<String, NewsItem> byRef,
    List<NewsItem> source,
  ) {
    final ref = (m['ref'] as String?)?.trim().toLowerCase();
    final hit = ref == null ? null : byRef[ref];
    if (hit != null) return hit;

    final title = (m['title'] as String?)?.trim().toLowerCase();
    if (title != null && title.length > 15) {
      for (final a in source) {
        final t = a.title.toLowerCase();
        if (t.length > 15 && (title.contains(t) || t.contains(title))) return a;
      }
    }
    return null;
  }

  static String? _shorten(String? s) =>
      s == null || s.length < 260 ? s : '${s.substring(0, 260)}\u2026';

  /// The edition the app can always write: the articles themselves, in the
  /// feed's shape. Not as good, and better than an empty screen.
  List<FeedPost> _plain(List<NewsItem> articles) => articles
      .take(3)
      .map((a) => FeedPost(
            id: 'p-${a.url.hashCode}',
            emoji: '📰',
            title: a.title,
            body: (a.summary?.isNotEmpty ?? false)
                ? a.summary!
                : 'Tap through to read this one at the source.',
            linkText: a.source ?? 'Read it at the source',
            linkUrl: a.url,
            source: a.source,
            imageUrl: a.imageUrl,
          ))
      .toList();

  // ─── Not the same story twice ─────────────────────────────────────────────

  /// The keys that identify a story for "have we already run this".
  ///
  /// Two, because one is not enough. The URL catches the identical article
  /// coming back from the same search tomorrow. The flattened headline catches
  /// the same story carried by a second publisher under its own link, which is
  /// how a single news event otherwise fills a whole edition on its own.
  @visibleForTesting
  static List<String> seenKeysFor(NewsItem n) {
    final url = n.url.trim().toLowerCase();
    // Query strings are where trackers live, and the same article arrives with
    // a different one every time it is fetched.
    final cut = url.indexOf('?');
    final bare = cut == -1 ? url : url.substring(0, cut);

    final title = n.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return [
      if (bare.isNotEmpty) 'u:$bare',
      if (title.length >= 12) 't:$title',
    ];
  }

  /// Build the record from what has already been published on this device.
  ///
  /// A post keeps the link it was written from, so the URL key seeds exactly.
  /// Its title is the headline the model wrote, not the publisher's, so the
  /// title key seeded here will usually miss - which costs nothing, because
  /// the URL is the key that catches the same article coming back and the
  /// title is only ever the second net, for the same story under a different
  /// link. Editions written from now on record both properly.
  void _seedSeenFromEditions() {
    for (final e in _editions) {
      final at = e.at.millisecondsSinceEpoch;
      for (final post in e.posts) {
        final url = post.linkUrl;
        if (url == null || url.isEmpty) continue;
        for (final k in seenKeysFor(NewsItem(title: post.title, url: url))) {
          // Keep the oldest stamp, so the TTL runs from when it was published.
          final prev = _seen[k];
          if (prev == null || at < prev) _seen[k] = at;
        }
      }
    }
  }

  /// Forget stories old enough that running one again is not a repeat.
  void _pruneSeen() {
    final cutoff =
        DateTime.now().subtract(_seenTtl).millisecondsSinceEpoch;
    _seen.removeWhere((_, at) => at < cutoff);
  }

  // ─── Storage ──────────────────────────────────────────────────────────────

  Future<void> _restoreSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_kSeen);
      if (raw == null) {
        // Nothing recorded yet, so seed it from the editions already on the
        // device. Without this the record starts empty on the build that
        // introduces it, and the very next edition happily repeats everything
        // written before it - which is the complaint, reproduced once more on
        // the machine that was supposed to have fixed it.
        _seedSeenFromEditions();
        _pruneSeen();
        if (_seen.isNotEmpty) await _persistSeen();
        debugPrint('[feed] seeded ${_seen.length} keys from stored editions');
        return;
      }
      final m = jsonDecode(raw) as Map;
      _seen
        ..clear()
        ..addAll(m.map((k, v) => MapEntry('$k', (v as num).toInt())));
      _pruneSeen();
      debugPrint('[feed] ${_seen.length} stories already published');
    } catch (e) {
      // A lost record costs one edition its freshness, never the screen.
      debugPrint('[feed] could not restore seen stories: $e');
    }
  }

  Future<void> _persistSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_kSeen, jsonEncode(_seen));
    } catch (e) {
      debugPrint('[feed] could not save seen stories: $e');
    }
  }

  Future<void> _restore() async {
    try {
      final p = await SharedPreferences.getInstance();
      _staleSchema = (p.getInt(_kSchema) ?? 1) < _schema;
      final raw = p.getString(_kEditions);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .whereType<Map>()
          .map((m) => FeedEdition.fromJson(m.cast<String, dynamic>()))
          .whereType<FeedEdition>()
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));
      _editions
        ..clear()
        ..addAll(list);
    } catch (e) {
      // Corrupt storage costs the archive, never the screen.
      debugPrint('[feed] could not restore editions: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(
        _kEditions,
        jsonEncode(_editions.map((e) => e.toJson()).toList()),
      );
      await p.setInt(_kSchema, _schema);
    } catch (e) {
      debugPrint('[feed] could not save editions: $e');
    }
  }

  /// Make a model's answer parseable without changing what it says.
  ///
  /// Two things get in the way, and both cost the whole edition its writing
  /// rather than one field. The answer may be wrapped in prose or code fences,
  /// so it is sliced to the outermost braces. And a writer laying a body out
  /// over two lines puts a raw newline inside a JSON string, which the format
  /// forbids and jsonDecode refuses outright. Between tokens a control
  /// character is only ever whitespace here, so turning every one of them into
  /// a space is safe and fixes the string case at the same time.
  @visibleForTesting
  static String repairJson(String s) {
    final a = s.indexOf('{');
    final b = s.lastIndexOf('}');
    final slice = (a < 0 || b <= a) ? s : s.substring(a, b + 1);
    return slice.replaceAll(RegExp(r'[\x00-\x1F]'), ' ');
  }
}
