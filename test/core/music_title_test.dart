import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/music_title.dart';

void main() {
  test('an ordinary title is left alone', () {
    expect(tidyMusicTitle('Yabesh Thapa - Kasari'), 'Yabesh Thapa - Kasari');
    expect(tidyMusicTitle('Never Gonna Give You Up'), 'Never Gonna Give You Up');
  });

  // Uploaders pad titles with what a search engine wants. None of it helps
  // somebody glancing at a pill under a timer.
  test('search-engine padding comes off the end', () {
    expect(tidyMusicTitle('Some Song (Official Music Video)'), 'Some Song');
    expect(tidyMusicTitle('Some Song [Official Video]'), 'Some Song');
    expect(tidyMusicTitle('Some Song (Lyrics)'), 'Some Song');
    expect(tidyMusicTitle('Some Song | Official Audio'), 'Some Song');
    expect(tidyMusicTitle('Some Song (Visualizer)'), 'Some Song');
  });

  test('several tails in a row all come off', () {
    expect(tidyMusicTitle('Some Song (Official Video) [HD]'), 'Some Song');
  });

  // The point is a readable name, not an aggressive one. Anything that is part
  // of how the track is actually known has to survive.
  test('brackets that are part of the name stay', () {
    expect(tidyMusicTitle('Song (Remix)'), 'Song (Remix)');
    expect(tidyMusicTitle('Song (feat. Someone)'), 'Song (feat. Someone)');
    expect(tidyMusicTitle('Song (Live at Wembley)'), 'Song (Live at Wembley)');
  });

  test('whitespace is collapsed', () {
    expect(tidyMusicTitle('  Some   Song  '), 'Some Song');
  });

  // Better the id-based label than an empty pill.
  test('a title that was nothing but padding returns null', () {
    expect(tidyMusicTitle('(Official Video)'), isNull);
    expect(tidyMusicTitle('   '), isNull);
  });
}
