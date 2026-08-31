import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/focus_music_store.dart';
import '../../../providers/focus_provider.dart';
import '../../../providers/focus_room_provider.dart';
import 'music_player_card.dart';

/// The room's music: shared state on the server, so everyone sees and hears the
/// same thing. A YouTube link genuinely plays together, lined up on the
/// server's clock; a Spotify link can only be a shared name.
class RoomMusicStrip extends StatelessWidget {
  const RoomMusicStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final room = context.watch<FocusRoomProvider>();
    return MusicPlayerCard(
      music: room.music,
      error: room.musicError,
      onSet: (v) => room.setMusic(v),
      onPausedChanged: room.setMusicPaused,
      emptyHint: 'paste an audio or YouTube link for the room',
      // Said plainly rather than buried in a help sheet. People WILL notice
      // they are out of step with a friend, and being told up front beats
      // discovering it and assuming it is broken.
      handOffNote: 'everyone opens this in their own Spotify, so you will drift',
    );
  }
}

/// The solo session's copy: same card, same link handling, stored on the device
/// because there is nobody to agree with.
class SoloMusicStrip extends StatefulWidget {
  const SoloMusicStrip({super.key});

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
  Widget build(BuildContext context) => MusicPlayerCard(
        music: _store.music,
        error: _store.error,
        onSet: (v) => _store.set(v),
        // The music follows the timer: pausing to take a call should not leave
        // the track playing on, and resuming should not need a second tap.
        sessionRunning: context.watch<FocusProvider>().isRunning,
        // No room-wide pause in a solo session: the player's own controls are
        // the whole story, and there is nobody to pause it for.
        emptyHint: 'paste an audio or YouTube link to play while you work',
        handOffNote: 'opens in your Spotify app',
      );
}
