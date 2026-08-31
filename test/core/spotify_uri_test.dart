import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/utils/spotify_uri.dart';

void main() {
  const id = '37i9dQZF1DXcBWIGoYBM5M';

  group('accepts every form a human actually pastes', () {
    for (final input in [
      'https://open.spotify.com/playlist/$id',
      'https://open.spotify.com/playlist/$id?si=abc123',
      'https://open.spotify.com/intl-de/playlist/$id',
      'http://open.spotify.com/playlist/$id',
      'spotify:playlist:$id',
      '  spotify:playlist:$id  ',
    ]) {
      test(input, () => expect(normaliseSpotifyUri(input), 'spotify:playlist:$id'));
    }
  });

  test('keeps the resource kind', () {
    expect(normaliseSpotifyUri('https://open.spotify.com/track/$id'), 'spotify:track:$id');
    expect(normaliseSpotifyUri('https://open.spotify.com/album/$id'), 'spotify:album:$id');
    expect(normaliseSpotifyUri('https://open.spotify.com/artist/$id'), 'spotify:artist:$id');
  });

  group('rejects', () {
    final bad = {
      'another host': 'https://evil.example/playlist/$id',
      // The one a suffix check would have let through.
      'host suffix attack': 'https://open.spotify.com.evil.example/playlist/$id',
      'javascript scheme': 'javascript:alert(1)',
      'path traversal in id': 'spotify:playlist:../../etc/passwd',
      'id too short': 'https://open.spotify.com/playlist/short',
      'unknown kind': 'spotify:userdata:$id',
      'not a url': 'not a url at all',
      'empty': '',
      'null': null,
      'absurdly long': 'https://open.spotify.com/playlist/${'x' * 5000}',
    };
    bad.forEach((name, input) {
      test(name, () => expect(normaliseSpotifyUri(input), isNull));
    });
  });
}
