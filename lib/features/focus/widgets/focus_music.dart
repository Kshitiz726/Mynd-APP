import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/focus_music_store.dart';
import '../../../providers/focus_provider.dart';
import '../../../providers/focus_room_provider.dart';
import 'music_bar.dart';

/// The room's music: shared state on the server, so everyone sees and hears the
/// same thing. Setting a link, pausing and the playhead all go through the
/// server and come back to every device, which is what makes it one room
/// listening rather than several people listening to the same song.
class RoomMusicStrip extends StatelessWidget {
  const RoomMusicStrip({super.key});

  @override
  Widget build(BuildContext context) {
    // Nothing to offer a room while the internet sources are off.
    //
    // A room's soundtrack is shared state on the server, so it only works for
    // a source every member can reach. Search and pasted links are switched
    // off (see MusicBar.internetMusicEnabled), and a file on one phone is
    // refused by FocusRoomProvider.setMusic because it cannot play on anyone
    // else's and its path carries the owner's name. That leaves no source at
    // all, so the strip would be a picker whose every result is an error -
    // broken functionality a reviewer meets on the way in, under guideline
    // 2.1. Hidden until the sources come back.
    if (!MusicBar.internetMusicEnabled) return const SizedBox.shrink();

    final room = context.watch<FocusRoomProvider>();
    return MusicBar(
      music: room.music,
      error: room.musicError,
      onSet: (v, {title}) => room.setMusic(v, title: title),
      // A room's pause is everybody's. There is no shared room timer to hang it
      // off - each person's clock is their own - so the bar keeps its own
      // pause here, and that one press reaches every device.
      onPausedChanged: room.setMusicPaused,
    );
  }
}

/// The solo session's copy: same bar, same link handling, stored on the device
/// because there is nobody to agree with.
class SoloMusicStrip extends StatefulWidget {
  const SoloMusicStrip({super.key, this.onScene = false});

  final bool onScene;

  @override
  State<SoloMusicStrip> createState() => _SoloMusicStripState();
}

class _SoloMusicStripState extends State<SoloMusicStrip> {
  final _store = FocusMusicStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onChange);
    _store.load();
  }

  @override
  void dispose() {
    _store.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => MusicBar(
        music: _store.music,
        error: _store.error,
        onSet: (v, {title}) => _store.set(v, title: title),
        onScene: widget.onScene,
        // The session's pause is the transport. Pausing to take a call should
        // not leave the track playing, resuming should not need a second tap,
        // and there is deliberately no second play button to disagree with it.
        sessionRunning: context.watch<FocusProvider>().isRunning,
      );
}
