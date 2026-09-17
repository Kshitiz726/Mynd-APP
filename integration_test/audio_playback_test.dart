import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

/// Does the audio a room shares actually come out of the speaker?
///
/// Every test so far checked that the music STATE reached the other device,
/// which it does, and none of them checked that a note was played - the room
/// tests drove the provider and never mounted the player at all. "The state is
/// correct" and "we are listening to the same thing" are different claims, and
/// only the second one is the feature.
///
/// This runs the exact sequence the music bar runs, against the exact URL a
/// search now produces, on a real device.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const ours = 'https://ourmynd-server.onrender.com/api/music/stream/Kpkr9.mp3';

  Future<String> tryPlay(String label, String url, {Duration? seekTo}) async {
    final player = ap.AudioPlayer();
    final events = <String>[];
    final sub = player.onPlayerStateChanged.listen((s) => events.add('$s'));
    try {
      await player.setAudioContext(ap.AudioContextConfig(
        focus: ap.AudioContextConfigFocus.mixWithOthers,
      ).build());
      await player.setReleaseMode(ap.ReleaseMode.loop);
      await player.setSource(ap.UrlSource(url));
      // The receiving side of a room seeks to where the room already is before
      // it presses play. The person who SET the track is at position zero and
      // skips this, which is exactly the asymmetry being tested.
      if (seekTo != null && seekTo > Duration.zero) await player.seek(seekTo);
      await player.resume();

      // Position advancing is the only honest proof. State can say "playing"
      // while a stalled stream sits at zero forever.
      Duration best = Duration.zero;
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        final p = await player.getCurrentPosition() ?? Duration.zero;
        if (p > best) best = p;
        if (best > (seekTo ?? Duration.zero) + const Duration(milliseconds: 900)) break;
      }
      final floor = (seekTo ?? Duration.zero) + const Duration(milliseconds: 900);
      final verdict = best > floor
          ? 'PLAYS (reached ${best.inMilliseconds}ms)'
          : 'SILENT (stuck at ${best.inMilliseconds}ms)';
      debugPrint('[audio] $label -> $verdict  events=$events');
      return verdict;
    } catch (e) {
      debugPrint('[audio] $label -> THREW $e  events=$events');
      return 'THREW $e';
    } finally {
      await sub.cancel();
      await player.dispose();
    }
  }

  testWidgets('the room stream URL actually plays on this device',
      (tester) async {
    final viaUs = await tryPlay('setter path, no seek', ours);
    debugPrint('[audio] RESULT setter=$viaUs');
    expect(viaUs, startsWith('PLAYS'),
        reason: 'the URL a search hands the room does not produce audio');
  });

  testWidgets('and still plays when a late joiner seeks into it',
      (tester) async {
    final joiner = await tryPlay('receiver path, seek 3s', ours,
        seekTo: const Duration(seconds: 3));
    debugPrint('[audio] RESULT receiver=$joiner');
    expect(joiner, startsWith('PLAYS'),
        reason: 'seeking before the stream is ready is what silences the '
            'person who did not choose the track');
  });
}
