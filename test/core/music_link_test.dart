import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/utils/music_link.dart';

void main() {
  const spotifyId = '37i9dQZF1DXcBWIGoYBM5M';
  const videoId = 'dQw4w9WgXcQ';
  const listId = 'PLFgquLnL59alCl_2TQvOiD5Vgm1hCaGSI';

  group('spotify: accepts every form a human actually pastes', () {
    for (final input in [
      'https://open.spotify.com/playlist/$spotifyId',
      'https://open.spotify.com/playlist/$spotifyId?si=abc123',
      'https://open.spotify.com/intl-de/playlist/$spotifyId',
      'http://open.spotify.com/playlist/$spotifyId',
      'spotify:playlist:$spotifyId',
      '  spotify:playlist:$spotifyId  ',
    ]) {
      test(input, () => expect(normaliseMusicUri(input), 'spotify:playlist:$spotifyId'));
    }
  });

  test('spotify: keeps the resource kind', () {
    expect(normaliseMusicUri('https://open.spotify.com/track/$spotifyId'),
        'spotify:track:$spotifyId');
    expect(normaliseMusicUri('https://open.spotify.com/album/$spotifyId'),
        'spotify:album:$spotifyId');
    expect(normaliseMusicUri('https://open.spotify.com/artist/$spotifyId'),
        'spotify:artist:$spotifyId');
  });

  group('youtube: accepts every form a human actually pastes', () {
    for (final input in [
      'https://www.youtube.com/watch?v=$videoId',
      'https://youtube.com/watch?v=$videoId',
      'https://m.youtube.com/watch?v=$videoId',
      'https://music.youtube.com/watch?v=$videoId',
      'https://www.youtube.com/watch?v=$videoId&t=42s',
      'https://youtu.be/$videoId',
      // The share sheet appends a tracking token; it must not reach the room.
      'https://youtu.be/$videoId?si=Xy7QpLm2',
      'https://www.youtube.com/shorts/$videoId',
      'https://www.youtube.com/embed/$videoId',
      'https://www.youtube.com/live/$videoId',
      'youtube:video:$videoId',
    ]) {
      test(input, () => expect(normaliseMusicUri(input), 'youtube:video:$videoId'));
    }
  });

  test('youtube: a playlist link is a playlist', () {
    expect(normaliseMusicUri('https://www.youtube.com/playlist?list=$listId'),
        'youtube:playlist:$listId');
  });

  test('youtube: on a watch URL carrying both, the video wins', () {
    // What the sender was actually looking at.
    expect(
      normaliseMusicUri('https://www.youtube.com/watch?v=$videoId&list=$listId'),
      'youtube:video:$videoId',
    );
  });

  test('the canonical form round-trips', () {
    for (final raw in [
      'https://youtu.be/$videoId',
      'https://open.spotify.com/track/$spotifyId',
      'https://www.youtube.com/playlist?list=$listId',
    ]) {
      final once = normaliseMusicUri(raw);
      expect(normaliseMusicUri(once), once, reason: 'not idempotent for $raw');
    }
  });

  test('provider decides whether it can play here', () {
    expect(parseMusicLink('https://youtu.be/$videoId')!.playsInApp, isTrue);
    // Spotify has no mobile path that produces audio inside our process.
    expect(parseMusicLink('spotify:track:$spotifyId')!.playsInApp, isFalse);
  });

  test('web URLs are rebuilt for handing to the OS', () {
    expect(parseMusicLink('https://youtu.be/$videoId')!.webUrl.toString(),
        'https://www.youtube.com/watch?v=$videoId');
    expect(parseMusicLink('spotify:track:$spotifyId')!.webUrl.toString(),
        'https://open.spotify.com/track/$spotifyId');
  });

  group('direct audio URLs are the audio-only provider', () {
    const mp3 = 'https://ice.somafm.com/groovesalad-128.mp3';
    test('an mp3 URL round-trips to its own URL', () {
      final l = parseMusicLink(mp3)!;
      expect(l.provider, MusicProvider.stream);
      expect(l.streamUrl, mp3);
      expect(l.audioOnly, isTrue);
      expect(l.playsInApp, isTrue);
      expect(normaliseMusicUri(l.uri), l.uri, reason: 'not idempotent');
    });

    test('the containers people actually paste', () {
      for (final u in [
        'https://example.com/track.m4a',
        'https://example.com/track.aac',
        'https://example.com/a/b/track.ogg',
        'https://example.com/track.opus',
        'https://example.com/track.flac',
        'https://example.com/live.m3u8',
        'http://example.com/station.pls',
        'https://example.com/TRACK.MP3',
      ]) {
        expect(parseMusicLink(u)?.provider, MusicProvider.stream, reason: u);
      }
    });

    test('a required query token survives, unlike a Spotify share token', () {
      const withToken = 'https://cdn.example.com/s.mp3?token=abc123&br=320';
      expect(parseMusicLink(withToken)!.streamUrl, withToken);
    });

    test('only YouTube and Spotify bring a picture', () {
      expect(parseMusicLink(mp3)!.audioOnly, isTrue);
      expect(parseMusicLink('https://youtu.be/$videoId')!.audioOnly, isFalse);
      expect(parseMusicLink('spotify:track:$spotifyId')!.audioOnly, isFalse);
    });

    test('a label falls back to the file name', () {
      expect(parseMusicLink(mp3)!.fileLabel, 'groovesalad-128.mp3');
    });
  });

  group('a file on this device', () {
    test('is audio-only, playable and NOT shareable', () {
      final l = musicLinkForFile('/var/mobile/Containers/Data/song.mp3')!;
      expect(l.provider, MusicProvider.file);
      expect(l.audioOnly, isTrue);
      expect(l.playsInApp, isTrue);
      // The privacy rule: a local path must never reach a room.
      expect(l.shareable, isFalse);
      expect(l.filePath, '/var/mobile/Containers/Data/song.mp3');
      expect(l.fileLabel, 'song.mp3');
    });

    test('round-trips through the canonical form', () {
      final l = musicLinkForFile('/tmp/a b/c+d.m4a')!;
      final back = MusicLink.parse(l.uri)!;
      expect(back.filePath, '/tmp/a b/c+d.m4a');
    });

    test('only audio extensions', () {
      expect(musicLinkForFile('/tmp/clip.mp4'), isNull);
      expect(musicLinkForFile('/tmp/notes.txt'), isNull);
      expect(musicLinkForFile('/tmp/noextension'), isNull);
      expect(musicLinkForFile('   '), isNull);
    });

    // No pasted text should ever become a local path: that would be a way to
    // point the player at an arbitrary file on the device.
    test('cannot be produced by pasting text', () {
      expect(parseMusicLink('/var/mobile/song.mp3'), isNull);
      expect(parseMusicLink('file:///var/mobile/song.mp3'), isNull);
      expect(parseMusicLink('/etc/passwd'), isNull);
    });

    test('everything else IS shareable', () {
      expect(parseMusicLink('https://youtu.be/$videoId')!.shareable, isTrue);
      expect(parseMusicLink('https://e.com/a.mp3')!.shareable, isTrue);
      expect(parseMusicLink('spotify:track:$spotifyId')!.shareable, isTrue);
    });
  });

  group('rejects', () {
    final bad = {
      'another host': 'https://evil.example/playlist/$spotifyId',
      // The one a suffix check would have let through.
      'spotify host suffix attack':
          'https://open.spotify.com.evil.example/playlist/$spotifyId',
      'youtube host suffix attack': 'https://youtube.com.evil.example/watch?v=$videoId',
      'youtu.be lookalike': 'https://youtu.be.evil.example/$videoId',
      'javascript scheme': 'javascript:alert(1)',
      'path traversal in id': 'spotify:playlist:../../etc/passwd',
      'spotify id too short': 'https://open.spotify.com/playlist/short',
      // 11 characters exactly, or it is not a video id.
      'youtube id too short': 'https://www.youtube.com/watch?v=abc',
      'youtube id too long': 'https://www.youtube.com/watch?v=${videoId}extra',
      'unknown spotify kind': 'spotify:userdata:$spotifyId',
      'youtube channel is not playable': 'https://www.youtube.com/@someuser',
      'not a url': 'not a url at all',
      'empty': '',
      'null': null,
      'absurdly long': 'https://open.spotify.com/playlist/${'x' * 5000}',
      // No extension means no way to tell audio from an HTML page, and
      // handing the player a web page fails silently.
      'a web page': 'https://example.com/some/article',
      'a bare host': 'https://example.com',
      'a video file': 'https://example.com/clip.mp4',
      'an image': 'https://example.com/cover.jpg',
      'ftp scheme': 'ftp://example.com/track.mp3',
    };
    bad.forEach((name, input) {
      test(name, () => expect(normaliseMusicUri(input), isNull));
    });
  });
}
