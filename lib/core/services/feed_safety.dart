/// What the Feed will not carry, whatever it is asked to carry.
///
/// The feed writes against an instruction document the user controls, and the
/// search queries are derived from it - so without this, "bring me porn" is a
/// working instruction. This is the one place that is not up to the user.
///
/// It is not prudishness. This app is built for ADHD brains, and the failure
/// it is guarding against is a compulsive-scroll surface delivered by the one
/// app somebody opened to get away from compulsive scrolling. A feed that can
/// be pointed at sexual content is a feed that will be, on the worst evening
/// somebody has, by the part of them that is least able to stop.
///
/// Word boundaries, not substrings. A substring match on 'sex' rejects
/// 'Middlesex', 'sexism' and 'homosexuality', and a safety filter that quietly
/// eats a story about discrimination law is its own kind of harm.
library;

const List<String> _blocked = [
  'porn', 'pornography', 'porno', 'xxx', 'nsfw', 'hentai', 'erotica',
  'erotic', 'nude', 'nudes', 'nudity', 'naked', 'sex', 'sexual', 'sexy',
  'fetish', 'bdsm', 'onlyfans', 'camgirl', 'escort', 'brothel', 'orgy',
  'masturbation', 'genitals', 'lingerie', 'stripper', 'strippers',
];

/// Terms that are only ever a request for the thing, not a report about it.
///
/// Kept apart from [_blocked] because these never appear in legitimate news
/// coverage, so they can be matched without the exemptions below.
const List<String> _hardBlocked = [
  'porn', 'pornography', 'porno', 'xxx', 'nsfw', 'hentai', 'onlyfans',
  'camgirl', 'bdsm', 'orgy',
];

/// Contexts in which the words above are ordinary journalism rather than the
/// thing itself: abuse reporting, law, health and education.
///
/// Without this the filter removes exactly the coverage that matters most -
/// a conviction for assault, a change to consent law, a sexual health study -
/// and does it silently.
const List<String> _exempt = [
  'assault', 'abuse', 'harassment', 'trafficking', 'exploitation',
  'consent law', 'education', 'health', 'crime', 'court', 'trial',
  'convicted', 'charged', 'investigation', 'discrimination', 'sexism',
  'harassment claim', 'survivor', 'victim',
];

bool _hasWord(String haystack, String word) =>
    RegExp('\\b${RegExp.escape(word)}\\b', caseSensitive: false)
        .hasMatch(haystack);

/// True when this text must not reach the feed.
///
/// [strict] is for the instruction document and the search queries built from
/// it, where there is no journalism to protect and the only reason the word is
/// present is that somebody asked for it.
bool isUnsafeForFeed(String text, {bool strict = false}) {
  if (text.trim().isEmpty) return false;
  final lower = text.toLowerCase();

  for (final w in _hardBlocked) {
    if (_hasWord(lower, w)) return true;
  }
  if (strict) {
    for (final w in _blocked) {
      if (_hasWord(lower, w)) return true;
    }
    return false;
  }

  final flagged = _blocked.any((w) => _hasWord(lower, w));
  if (!flagged) return false;
  // Flagged, but it may be coverage rather than the thing.
  return !_exempt.any((e) => lower.contains(e));
}

/// The instruction document with any request for this stripped out.
///
/// Lines rather than the whole document, so one bad sentence costs that
/// sentence and not everything else somebody carefully wrote.
String stripUnsafeInstructions(String text) {
  final kept = text
      .split('\n')
      .where((line) => !isUnsafeForFeed(line, strict: true))
      .join('\n');
  return kept.trim();
}
