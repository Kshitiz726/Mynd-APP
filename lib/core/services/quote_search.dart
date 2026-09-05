import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One quotation and the person who said it.
class Quote {
  const Quote({required this.text, required this.author});
  final String text;
  final String author;
}

/// Quotations from the web, chosen by theme rather than at random.
///
/// Three sources, tried in order, because a keyless quotations endpoint is
/// exactly the kind of service that quietly disappears - the one this started
/// on (quotable.io) was already refusing connections when it was checked. Two
/// of the three could go the same way without the card ever showing a gap.
///
/// Only a theme word ever leaves the device. The person's memory picks which
/// themes to ask for, and that selection happens here, on the phone: the
/// request that goes out says "Perseverance", never anything about them.
class QuoteSearch {
  QuoteSearch._();
  static final QuoteSearch instance = QuoteSearch._();

  final _client = http.Client();

  /// Cached per theme for the life of the process. A day of lines asks for
  /// several themes at once and the same one comes up more than once.
  final Map<String, List<Quote>> _cache = {};

  /// The vocabulary the themed source actually indexes.
  ///
  /// Asking for a tag it does not have returns nothing rather than an error,
  /// so a theme that is not on this list is a silently empty request. Taken
  /// from its own /api/tags.
  static const themes = <String>[
    'Courage', 'Perseverance', 'Failure', 'Change', 'Self', 'Wisdom',
    'Happiness', 'Work', 'Health', 'Faith', 'Friendship', 'Family', 'Time',
    'Success', 'Motivational', 'Inspirational', 'Wellness', 'Pain',
    'Gratitude', 'Creativity', 'Knowledge', 'Freedom', 'Character', 'Life',
    'Truth', 'Future', 'Opportunity', 'Virtue', 'Nature', 'Love',
  ];

  /// Quotations for [themes], enough of them to fill a day.
  ///
  /// Short ones only. The card gives a quotation two lines before it ellipses,
  /// and a paragraph from Cicero that gets cut off mid-clause is worse than a
  /// plain sentence that fits.
  Future<List<Quote>> forThemes(List<String> wanted, {int want = 12}) async {
    final out = <String, Quote>{};

    await Future.wait(wanted.map((t) async {
      try {
        for (final q in await _themed(t)) {
          out[q.text] = q;
        }
      } catch (e) {
        debugPrint('[quote] theme "$t" failed: $e');
      }
    }));

    // Topping up rather than replacing. The themed source returns only a
    // handful per tag, so on its own it cannot fill twelve slots, and a day
    // that repeats four quotations three times each is the wallpaper problem
    // this was meant to fix.
    if (out.length < want) {
      for (final source in [_zen, _corpus]) {
        if (out.length >= want) break;
        try {
          for (final q in await source()) {
            out[q.text] = q;
          }
        } catch (e) {
          debugPrint('[quote] top-up source failed: $e');
        }
      }
    }

    final list = out.values.toList()..shuffle(Random());
    return list.take(want).toList();
  }

  Future<List<Quote>> _themed(String theme) async {
    final hit = _cache[theme];
    if (hit != null) return hit;

    final uri = Uri.https('api.quotable.kurokeita.dev', '/api/quotes/random', {
      // The API rejects anything but 10/25/50/100, with a 400 rather than a
      // clamp, so this is not a number to tune casually.
      'limit': '10',
      'tags': theme,
    });
    final res = await _get(uri);
    if (res == null) return const [];

    final body = jsonDecode(res) as Map<String, dynamic>;
    final quotes = (body['quotes'] as List?) ?? const [];
    final out = <Quote>[];
    for (final q in quotes) {
      final m = q as Map<String, dynamic>;
      // The author arrives as an object here and as a plain string elsewhere.
      final a = m['author'];
      final name = a is Map ? a['name'] as String? : a as String?;
      final text = m['content'] as String?;
      final quote = _clean(text, name);
      if (quote != null) out.add(quote);
    }
    _cache[theme] = out;
    return out;
  }

  /// A fresh batch of well-known quotations, no theme. Roughly fifty per call.
  Future<List<Quote>> _zen() async {
    final res = await _get(Uri.https('zenquotes.io', '/api/quotes'));
    if (res == null) return const [];
    final list = jsonDecode(res) as List;
    return [
      for (final q in list)
        if (_clean((q as Map)['q'] as String?, q['a'] as String?)
            case final Quote v)
          v,
    ];
  }

  /// A fixed corpus, read from a random offset so it is not the same hundred
  /// every time. The last resort before the offline bank.
  Future<List<Quote>> _corpus() async {
    final skip = Random().nextInt(1300);
    final res = await _get(Uri.https('dummyjson.com', '/quotes', {
      'limit': '100',
      'skip': '$skip',
    }));
    if (res == null) return const [];
    final body = jsonDecode(res) as Map<String, dynamic>;
    return [
      for (final q in (body['quotes'] as List? ?? const []))
        if (_clean((q as Map)['quote'] as String?, q['author'] as String?)
            case final Quote v)
          v,
    ];
  }

  Future<String?> _get(Uri uri) async {
    try {
      final res = await _client.get(uri, headers: {
        'User-Agent': 'Mynd/1.0 (https://ourmynd.app; contact via app store)',
      }).timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) {
        debugPrint('[quote] ${uri.host} returned ${res.statusCode}');
        return null;
      }
      // Decoded as UTF-8 explicitly. `body` falls back to latin1 when the
      // response carries no charset, which these APIs often do not, and that
      // turned "Thich Nhat Hanh" into mojibake on the card - every accented
      // name in the corpus was arriving mangled.
      return utf8.decode(res.bodyBytes, allowMalformed: true);
    } catch (e) {
      debugPrint('[quote] ${uri.host} failed: $e');
      return null;
    }
  }

  @visibleForTesting
  static Quote? debugClean(String? text, String? author) => _clean(text, author);

  /// Usable, or null. Length is the real filter: see [forThemes].
  static Quote? _clean(String? text, String? author) {
    final t = (text ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    final a = (author ?? '').trim();
    if (t.isEmpty || t.length > 150) return null;
    // "unknown" is not an attribution, and the whole point here is that
    // somebody said it.
    if (a.isEmpty || a.toLowerCase().startsWith('unknown')) return null;
    return Quote(text: t, author: a);
  }
}
