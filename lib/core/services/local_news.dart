import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Headlines for a place, from Google News' public RSS.
///
/// RSS rather than a news API, and the reason is not laziness: every keyed news
/// service wants a paid plan and an account, and putting a key in the app to
/// fetch public headlines would be a key anybody could pull out of the binary.
/// This endpoint needs no key, no account and no quota, and returns exactly the
/// headlines a search on the site would show.
///
/// Only titles are read. The body of a story is somebody's copyrighted
/// reporting, and nothing here needs it: a headline is enough to know what the
/// day feels like where somebody is.
class LocalNews {
  /// Up to [limit] headlines for [place], most recent first.
  ///
  /// Returns empty rather than throwing on every failure. Local news is
  /// flavour on top of a motivation line, so no signal, a place that means
  /// nothing to the index, or a service having a bad day all degrade to a line
  /// written without it.
  static Future<List<String>> headlines(String place, {int limit = 6}) async {
    if (place.trim().isEmpty) return const [];
    final q = Uri.encodeQueryComponent(place.trim());
    final url = Uri.parse(
      'https://news.google.com/rss/search?q=$q&hl=en&gl=US&ceid=US:en',
    );
    try {
      final res = await http.get(url).timeout(const Duration(seconds: 6));
      if (res.statusCode != 200) return const [];
      return _titles(utf8.decode(res.bodyBytes), limit: limit);
    } catch (e) {
      debugPrint('[motivation] news lookup failed: $e');
      return const [];
    }
  }

  /// Pull the item titles out of an RSS document.
  ///
  /// Deliberately not a full XML parse. The shape needed here is one tag inside
  /// another, the feed is machine generated and stable, and adding an XML
  /// dependency to read one element would be the larger cost. The first two
  /// titles in the document belong to the channel rather than to any story, so
  /// only titles inside an <item> are taken.
  @visibleForTesting
  static List<String> titles(String xml, {int limit = 6}) =>
      _titles(xml, limit: limit);

  static List<String> _titles(String xml, {required int limit}) {
    final out = <String>[];
    final items = RegExp(r'<item\b[\s\S]*?</item>', caseSensitive: false);
    final title = RegExp(r'<title>([\s\S]*?)</title>', caseSensitive: false);
    for (final item in items.allMatches(xml)) {
      final m = title.firstMatch(item.group(0)!);
      if (m == null) continue;
      final t = _unescape(m.group(1)!).trim();
      if (t.isEmpty) continue;
      out.add(t);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// The handful of entities a feed actually uses, plus numeric ones.
  ///
  /// Headlines are full of ampersands and curly quotes, and "Bath &amp; North
  /// East Somerset" read out to somebody as-is is the kind of detail that makes
  /// a whole feature look broken.
  static String _unescape(String s) {
    var t = s
        .replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
    t = t.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });
    // Last, or an escaped entity like &amp;quot; would be unescaped twice.
    return t.replaceAll('&amp;', '&');
  }
}
