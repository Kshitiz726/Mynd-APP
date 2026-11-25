import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:ourmynd/core/theme/app_theme.dart';
import 'package:ourmynd/core/utils/music_link.dart';
import 'package:ourmynd/features/focus/widgets/focus_music.dart';
import 'package:ourmynd/features/focus/widgets/music_bar.dart';
import 'package:ourmynd/providers/focus_room_provider.dart';
import 'package:ourmynd/providers/settings_provider.dart';

/// A room never offers a soundtrack it cannot deliver.
///
/// Three facts have to hold together, and the room is where they collide:
///
///   1. A room's music is shared state on the server, so every member plays
///      the same thing.
///   2. The internet sources - the Audius search and pasted links - are
///      switched off (MusicBar.internetMusicEnabled).
///   3. A file on one phone is refused for a room, because it cannot play on
///      anybody else's and its path carries the owner's name.
///
/// Together those leave a room with no usable source at all. A picker whose
/// every result is an error is broken functionality in the reviewer's path,
/// which is guideline 2.1 and the kind of thing that costs weeks. So while
/// the sources are off the strip shows nothing.
///
/// The solo session is deliberately not covered by that: a file on your own
/// phone plays on your own phone, so SoloMusicStrip stays.
void main() {
  testWidgets('a room shows no music strip while the sources are off',
      (tester) async {
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => FocusRoomProvider()),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: RoomMusicStrip()),
      ),
    ));
    await tester.pump();

    // Not merely "no error showing": no bar at all, so there is nothing to
    // tap and nothing to be refused.
    expect(find.byType(MusicBar), findsNothing);
  });

  test('turning the sources back on is what brings the room strip back', () {
    // Pins the dependency rather than the value. If someone flips the flag,
    // this test is the note saying the room strip returns with it and has to
    // be checked against a room that can actually share a source.
    expect(MusicBar.internetMusicEnabled, isFalse);
  });

  test('a file on this phone is not shareable with a room', () {
    // The other half of why the strip is hidden. If this ever starts
    // returning a shareable link, a room could broadcast a path that exists
    // on exactly one device and carries its owner's name.
    final link = musicLinkForFile('/var/mobile/Containers/Data/song.mp3');
    expect(link, isNotNull);
    expect(link!.shareable, isFalse);
  });
}
