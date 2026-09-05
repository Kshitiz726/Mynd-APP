import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// A photograph from the web, searched by what the line is actually about.
///
/// Wikimedia Commons, for three reasons that ruled out the alternatives:
/// it needs no key and no account, so nothing secret ships in the binary; its
/// results are freely licensed, which a decorative photo in a shipping app
/// actually needs; and it is not going to be retired next quarter the way the
/// keyless photo endpoints keep being.
///
/// Searched rather than random. A random picture under a sentence about your
/// week is decoration; one picked from the same words is the thing the card is
/// for.
class PhotoSearch {
  PhotoSearch._();
  static final PhotoSearch instance = PhotoSearch._();

  static final _rand = Random();
  final _client = http.Client();

  /// Cached per query for the life of the process, because a day of lines asks
  /// for several pictures at once and the same theme comes up more than once.
  final Map<String, List<String>> _cache = {};

  /// A photo URL for [query], or null when the search found nothing usable.
  ///
  /// Picks at random from the results rather than taking the first: the top hit
  /// for a given word is the same photograph every time, which is the exact
  /// complaint this is meant to answer.
  Future<String?> find(String query, {int width = 900}) async {
    final results = await _results(query, width);
    if (results.isEmpty) return null;
    return results[_rand.nextInt(results.length)];
  }

  /// The first of [queries] that finds anything, most specific first.
  ///
  /// Necessary rather than tidy: a full-text search narrows fast, and a query
  /// built by gluing a mood phrase to a subject phrase ("mountain sunrise path
  /// uphill") returns zero results while either half alone returns hundreds.
  /// Without the retry the specific queries silently produced no picture at
  /// all, which is indistinguishable from the feature being switched off.
  /// [minResults] is what makes this randomise rather than merely succeed.
  /// The narrow queries land between zero and five hits, and a query with one
  /// hit hands every person on that mood the identical photograph, which is
  /// the complaint this was built to answer. A query that thin is treated as a
  /// miss and the broader one is used instead.
  Future<String?> findAny(
    List<String> queries, {
    int width = 900,
    int minResults = 8,
  }) async {
    final pool = await poolFor(queries, width: width, minResults: minResults);
    if (pool.isEmpty) return null;
    return pool[_rand.nextInt(pool.length)];
  }

  /// Every usable result for the first query in [queries] that returns enough
  /// of them.
  ///
  /// Exposed as a pool rather than a single pick so callers wanting several
  /// pictures for one theme can search once and still get a different
  /// photograph each. Collapsing that to one lookup returning one URL is
  /// faster and gives every line the same picture, which is the thing this is
  /// supposed to avoid.
  Future<List<String>> poolFor(
    List<String> queries, {
    int width = 900,
    int minResults = 8,
  }) async {
    List<String>? thin;
    for (final q in queries) {
      if (q.trim().isEmpty) continue;
      final results = await _results(q, width);
      if (results.length >= minResults) return results;
      // Kept, in case every query turns out to be thin: one photograph that
      // matches beats none at all.
      if (results.isNotEmpty) thin ??= results;
    }
    return thin ?? const [];
  }

  Future<List<String>> _results(String query, int width) async {
    final key = '$query@$width';
    final hit = _cache[key];
    if (hit != null) return hit;

    final uri = Uri.https('commons.wikimedia.org', '/w/api.php', {
      'action': 'query',
      'generator': 'search',
      // Namespace 6 is File:. bitmap excludes the diagrams, coats of arms and
      // svg logos that otherwise dominate a Commons text search.
      'gsrsearch': '$query filetype:bitmap',
      'gsrnamespace': '6',
      'gsrlimit': '40',
      'prop': 'imageinfo',
      'iiprop': 'url',
      // A thumbnail, not the original. Commons originals are routinely 20MB
      // and this is a strip behind two lines of text.
      'iiurlwidth': '$width',
      'format': 'json',
      'origin': '*',
    });

    try {
      final res = await _client.get(uri, headers: {
        // Wikimedia asks for a real one and rate-limits anonymous clients that
        // do not send it.
        'User-Agent': 'Mynd/1.0 (https://ourmynd.app; contact via app store)',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        debugPrint('[photo] search failed ${res.statusCode} for "$query"');
        return const [];
      }
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      final pages = (json['query'] as Map<String, dynamic>?)?['pages']
          as Map<String, dynamic>?;
      if (pages == null) return const [];

      final out = <String>[];
      for (final page in pages.values) {
        final info = ((page as Map<String, dynamic>)['imageinfo'] as List?)
            ?.firstOrNull as Map<String, dynamic>?;
        final url = info?['thumburl'] as String?;
        if (url == null) continue;
        // Commons holds a great deal that is not a photograph. Cheap filter on
        // the filename, because fetching each one to find out costs a request.
        final lower = url.toLowerCase();
        if (lower.contains('logo') ||
            lower.contains('icon') ||
            lower.contains('diagram') ||
            lower.contains('map_of') ||
            lower.contains('chart')) {
          continue;
        }
        out.add(url);
      }
      _cache[key] = out;
      return out;
    } catch (e) {
      // Never fatal. A card with no photograph still reads; a card that waited
      // on a dead network does not appear at all.
      debugPrint('[photo] search error for "$query": $e');
      return const [];
    }
  }
}
