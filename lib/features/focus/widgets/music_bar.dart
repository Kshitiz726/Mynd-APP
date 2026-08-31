import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/music_link.dart';
import '../../../core/utils/music_playback.dart';
import '../../../core/utils/toast.dart';
import '../../../models/room_music.dart';
import '../../../widgets/om_tappable.dart';

/// One line of music under the timer, and the engine that plays it.
///
/// Deliberately not a player. The session's own pause is the transport: a
/// focus screen should have one thing to press, and a second set of play
/// controls sitting under the first only invites the question of which one
/// wins. So this is a name and a way to change it, nothing more.
///
/// Two providers, two capabilities:
///
///   Audio links, files on the device and YouTube all play HERE, out of Mynd.
///
///   Spotify cannot play inside any third-party app on mobile. Their Web
///   Playback SDK needs EME/Widevine and is unsupported in a webview, and the
///   App Remote SDK is a remote control for the Spotify app rather than a
///   source of audio. A Spotify link degrades honestly to a hand-off, and the
///   line says so instead of letting someone find out by pressing play.
class MusicBar extends StatefulWidget {
  const MusicBar({
    super.key,
    required this.music,
    required this.onSet,
    this.onPausedChanged,
    this.error,
    this.sessionRunning = true,
    this.onScene = false,
  });

  final RoomMusic? music;

  /// Called with a raw pasted string, or null to stop.
  final ValueChanged<String?> onSet;

  /// Pause/resume for everyone in a room. Null in a solo session, where the
  /// timer is the only thing that pauses anything.
  final ValueChanged<bool>? onPausedChanged;

  final String? error;

  /// Whether the focus timer itself is running.
  ///
  /// The music follows it in both directions: pausing to take a call should not
  /// leave the track playing, and resuming should not need a second tap.
  final bool sessionRunning;

  /// True when an ambience scene is behind this, which flips the colours to
  /// white so the line stays readable over artwork.
  final bool onScene;

  @override
  State<MusicBar> createState() => _MusicBarState();
}

/// The size the hidden YouTube player is laid out at.
///
/// Not zero, and that is the whole point: iOS throttles or suspends media in a
/// webview with no area, so a 0x0 player is a player that stops playing. It is
/// given a real box and then displaced out of a hard clip instead.
const double _playerBox = 188;

class _MusicBarState extends State<MusicBar> {
  YoutubePlayerController? _yt;
  StreamSubscription<YoutubePlayerValue>? _sub;

  /// What the controller currently holds, so an unrelated rebuild does not
  /// reload the track and restart it from zero.
  String? _loadedUri;

  /// The last play/pause we asked for, so the desired state is only ever
  /// asserted on a change. Re-asserting it on every rebuild is how music came
  /// back on underneath a paused timer.
  bool? _commandedPlay;

  Timer? _drift;

  YoutubeError _ytError = YoutubeError.none;
  Duration _duration = Duration.zero;

  /// The audio-only engine, used for direct stream URLs and device files.
  ///
  /// Separate from the YouTube controller rather than hidden behind one
  /// interface, because they differ in the way that matters: this one has no
  /// picture, and no terms attached to showing one.
  ap.AudioPlayer? _audio;
  final List<StreamSubscription<dynamic>> _audioSubs = [];
  String? _audioError;

  bool get _isRoom => widget.onPausedChanged != null;

  /// Whether YouTube refused this video outright, as opposed to still loading.
  ///
  /// Worth its own state because it is common and silent: a large share of
  /// popular music videos, and most 24/7 study streams, are marked
  /// "not embeddable" by their uploader. Without this the line would just say
  /// the track name forever while nothing played.
  bool get _refused => switch (_ytError) {
        YoutubeError.notEmbeddable ||
        YoutubeError.sameAsNotEmbeddable ||
        YoutubeError.sameAsNotEmbeddable2 ||
        YoutubeError.videoNotFound ||
        YoutubeError.cannotFindVideo ||
        YoutubeError.invalidParam ||
        YoutubeError.html5Error =>
          true,
        _ => false,
      };

  String get _refusalReason => switch (_ytError) {
        YoutubeError.videoNotFound || YoutubeError.cannotFindVideo =>
          'that video is private or gone',
        YoutubeError.notEmbeddable ||
        YoutubeError.sameAsNotEmbeddable ||
        YoutubeError.sameAsNotEmbeddable2 =>
          "the uploader doesn't allow this one outside YouTube",
        _ => "that one won't play here",
      };

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MusicBar old) {
    super.didUpdateWidget(old);
    // A room's pause belongs to everyone, so the timer states the intent and
    // waits for the server to say so; the local player then follows the same
    // flag every other device is following. Solo has nobody to tell.
    if (old.sessionRunning != widget.sessionRunning) {
      widget.onPausedChanged?.call(!widget.sessionRunning);
    }
    _sync();
  }

  @override
  void dispose() {
    _drift?.cancel();
    _sub?.cancel();
    _yt?.close();
    _disposeAudio();
    super.dispose();
  }

  void _disposeAudio() {
    for (final s in _audioSubs) {
      s.cancel();
    }
    _audioSubs.clear();
    _audio?.dispose();
    _audio = null;
  }

  /// Start (or re-point) the audio-only engine.
  Future<void> _loadAudio(MusicLink link,
      {required bool play, Duration? at}) async {
    final player = _audio ??= ap.AudioPlayer();
    if (_audioSubs.isEmpty) {
      _audioSubs.add(player.onDurationChanged.listen((d) {
        if (mounted && d != _duration) setState(() => _duration = d);
      }));
    }
    try {
      // Playback category, so audio keeps going when the phone is locked and
      // mixes politely rather than stopping whatever else is playing.
      await player.setAudioContext(ap.AudioContextConfig(
        focus: ap.AudioContextConfigFocus.mixWithOthers,
      ).build());
      // The engine repeats it for us, so there is no gap and no state to keep.
      await player.setReleaseMode(ap.ReleaseMode.loop);
      // A device file is read straight off disk; a stream is fetched. Same
      // engine either way, so everything downstream is identical.
      final path = link.filePath;
      await player.setSource(path != null
          ? ap.DeviceFileSource(path)
          : ap.UrlSource(link.streamUrl!));
      if (at != null && at > Duration.zero) await player.seek(at);
      if (play) await player.resume();
      if (mounted && _audioError != null) setState(() => _audioError = null);
    } catch (e) {
      debugPrint('[focus-music] audio load failed: $e');
      if (mounted) {
        setState(() => _audioError = link.filePath != null
            ? 'that file would not play'
            : 'that audio link would not play');
      }
    }
  }

  /// Bring the engine in line with what the session says is playing.
  void _sync() {
    final music = widget.music;
    final link = music?.link;

    // Nothing playable in-app: tear the webview down rather than leaving it
    // parked. It is the most expensive thing on this screen.
    if (music == null || link == null || !music.playsInApp) {
      _disposeAudio();
      _drift?.cancel();
      _drift = null;
      _sub?.cancel();
      _sub = null;
      _yt?.close();
      _yt = null;
      _loadedUri = null;
      _commandedPlay = null;
      _ytError = YoutubeError.none;
      _duration = Duration.zero;
      return;
    }

    if (_loadedUri == music.uri) {
      _applyDesiredPlayback();
      return;
    }
    _loadedUri = music.uri;
    // A new track gets a clean slate, or the previous one's refusal would hide
    // a working track.
    _ytError = YoutubeError.none;
    _duration = Duration.zero;

    // Where the room already is, not the beginning. Someone joining twenty
    // minutes in hears what everybody else hears.
    final at = music.positionAt(DateTime.now());
    final shouldPlay = widget.sessionRunning && !music.paused;
    _commandedPlay = shouldPlay;

    // A direct audio URL or a file has no picture and needs no webview.
    if (link.audioOnly) {
      _sub?.cancel();
      _sub = null;
      _yt?.close();
      _yt = null;
      // Seek only where there is a room clock to line up with. Solo has none,
      // and seeking to a room position that does not exist is how the audio
      // ended up starting past the end of the track.
      _loadAudio(link, play: shouldPlay, at: _isRoom ? at : null);
      _startDriftCorrection();
      return;
    }

    _disposeAudio();
    if (_yt == null) {
      _yt = YoutubePlayerController(
        params: const YoutubePlayerParams(
          // The player is never seen, so its own chrome is pointless, and a
          // WKWebView that accepts pointers would swallow drags meant for the
          // screen behind it.
          showControls: false,
          pointerEvents: PointerEvents.none,
          showFullscreenButton: false,
          playsInline: true,
          // Do not trail unrelated videos after a focus track ends.
          strictRelatedVideos: true,
          // youtube-nocookie.com: no cookie is set unless playback starts.
          privacyEnhancedMode: true,
          // Repeat rather than fall silent. This flag is what wraps a playlist
          // round to its first video; a single video is handled by _loopAgain
          // below, because the IFrame API only honours loop for a lone video
          // when it was given as a one-item playlist, which is not how
          // loadVideoById works.
          loop: true,
        ),
      );
      var wasEnded = false;
      _sub = _yt!.stream.listen((v) {
        if (!mounted) return;
        // Only the transition into ended, never the state sitting there: the
        // stream re-emits whenever anything on the value changes, and
        // restarting on each of those would fight the seek.
        final justEnded = v.playerState == PlayerState.ended && !wasEnded;
        wasEnded = v.playerState == PlayerState.ended;
        if (v.error != _ytError || v.metaData.duration != _duration) {
          setState(() {
            _ytError = v.error;
            _duration = v.metaData.duration;
          });
        }
        if (justEnded) _loopAgain();
      });
    }

    // load* autoplays, cue* only prepares. Choosing between them is what makes
    // a fresh mount respect a paused session: switching the scene wraps the
    // screen in a Stack, which rebuilds this from scratch, and a plain load
    // would restart the music underneath a paused timer.
    final start = at.inSeconds.toDouble();
    _quietly(() => switch (playerLoadAction(
          isPlaylist: link.kind == 'playlist',
          sessionRunning: widget.sessionRunning,
          roomPaused: music.paused,
        )) {
          PlayerLoadAction.loadPlaylist => _yt!.loadPlaylist(
              list: [link.id], listType: ListType.playlist, startSeconds: start),
          PlayerLoadAction.cuePlaylist => _yt!.cuePlaylist(
              list: [link.id], listType: ListType.playlist, startSeconds: start),
          PlayerLoadAction.loadVideo =>
            _yt!.loadVideoById(videoId: link.id, startSeconds: start),
          PlayerLoadAction.cueVideo =>
            _yt!.cueVideoById(videoId: link.id, startSeconds: start),
        });

    _startDriftCorrection();
  }

  /// Play or pause to match the session, but only when that has changed.
  ///
  /// Edge-triggered on purpose. Asserting the desired state on every rebuild
  /// would mean an unrelated repaint could restart a track, which is the shape
  /// of every playback bug this screen has had.
  void _applyDesiredPlayback() {
    final music = widget.music;
    if (music == null) return;
    final play = widget.sessionRunning && !music.paused;
    if (play == _commandedPlay) return;
    _commandedPlay = play;

    final audio = _audio;
    if (audio != null) {
      play ? audio.resume() : audio.pause();
      return;
    }
    final yt = _yt;
    if (yt == null || _refused) return;
    _quietly(play ? yt.playVideo : yt.pauseVideo);
  }

  /// Play the finished track again from the top.
  ///
  /// A focus session outlasts any one song, and silence twenty minutes in is
  /// worse than hearing the same track twice - so a track repeats until
  /// somebody chooses a different one. Nothing has to stop the loop: setting a
  /// new link comes through _sync with a new uri and loads over the top of it.
  void _loopAgain() {
    final yt = _yt;
    if (yt == null || _refused) return;
    // Whatever was holding the music silent still holds. A track cannot
    // normally reach the end while paused, but a race between a pause and the
    // last second of a track should not restart it.
    if (!widget.sessionRunning || (widget.music?.paused ?? false)) return;
    // A playlist wraps on its own (loop is set on the player). Seeking to zero
    // here would instead trap everyone on the last video forever.
    if (widget.music?.link?.kind != 'video') return;
    debugPrint('[focus-music] track ended, going round again');
    _quietly(() async {
      await yt.seekTo(seconds: 0, allowSeekAhead: true);
      await yt.playVideo();
    });
  }

  /// Run a player command without letting its failure become an unhandled
  /// async error.
  ///
  /// Every command goes through the JS bridge, which waits for the iframe to
  /// report ready and throws TimeoutException after 30 seconds. A webview that
  /// never initialises - no network on a train, say - would otherwise throw
  /// from a future nobody is awaiting. Music failing is not a reason to take
  /// the focus session down with it.
  void _quietly(Future<void> Function() command) {
    command().catchError((Object e) {
      debugPrint('[focus-music] player command failed: $e');
    });
  }

  /// Nudge back into line when a device falls behind.
  ///
  /// Buffering, a backgrounded app, or a slow network all put one person out of
  /// step with the rest of the room. Re-seeking on a threshold rather than
  /// continuously, because every correction is an audible rebuffer: four
  /// seconds is past the point anyone would call it "together" and well clear
  /// of the jitter a healthy stream produces on its own.
  void _startDriftCorrection() {
    _drift?.cancel();
    if (!_isRoom) return; // solo: nothing to sync to
    _drift = Timer.periodic(const Duration(seconds: 20), (_) async {
      final music = widget.music;
      final yt = _yt;
      if (music == null || yt == null || music.paused || !mounted) return;
      // A playlist's playhead is per-video, so the room's elapsed time says
      // nothing about where this device is inside the current track.
      if (music.link?.kind != 'video') return;
      try {
        final actual = await yt.currentTime;
        // Wrapped by the track length, because the room's playhead keeps
        // counting up across repeats. Without this, the first loop would put
        // the target past the end of the track and every device would be
        // yanked back to a position that does not exist.
        final target =
            loopedPosition(music.positionAt(DateTime.now()), _duration)
                .inSeconds
                .toDouble();
        if ((actual - target).abs() > 4) {
          await yt.seekTo(seconds: target, allowSeekAhead: true);
        }
      } catch (_) {
        // The webview can be gone mid-await. Drift correction is a nicety.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.music;
    final link = music?.link;
    final inApp = music != null && music.playsInApp;
    final refused = inApp && !(link?.audioOnly ?? false) && _refused;
    final external = music != null && (!inApp || refused);

    return Stack(
      // Clips the player out of sight. Not decoration: see below.
      clipBehavior: Clip.hardEdge,
      children: [
        // The YouTube player, kept mounted and playing but moved outside the
        // clip so nothing of it is seen.
        //
        // Laid out at full size and merely displaced, rather than sized to zero
        // as the usual recipe suggests: iOS throttles or suspends media in a
        // webview with no area. Painting an opaque layer over it does not work
        // either - iOS composites a WKWebView in the native hierarchy, above
        // Flutter's own content, so the cover was simply invisible.
        //
        // This is a deliberate departure from YouTube's API Terms, which
        // require the embedded player to stay visible and unobscured. Anj asked
        // for it explicitly and repeatedly, knowing the consequence: App Review
        // can reject the build and YouTube can revoke API access. Confined to
        // this one block so it is the first thing to undo if either happens.
        if (inApp && !(link?.audioOnly ?? false) && _yt != null)
          Positioned(
            left: -_playerBox * 4,
            top: 0,
            width: _playerBox,
            height: _playerBox,
            child: IgnorePointer(
              child: YoutubePlayer(
                controller: _yt!,
                aspectRatio: 1,
                enableFullScreenOnVerticalDrag: false,
                autoFullScreen: false,
              ),
            ),
          ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // A room needs its own pause, because a room has no shared
                // timer to inherit one from: each person's clock is their own,
                // so the music is the only thing everybody is actually on.
                if (_isRoom && inApp && !refused) ...[
                  _RoundButton(
                    icon: (music.paused) ? LucideIcons.play : LucideIcons.pause,
                    onScene: widget.onScene,
                    onTap: () {
                      Haptics.light();
                      widget.onPausedChanged!(!music.paused);
                    },
                  ),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(child: _pill(context, music, external: external)),
                if (external) ...[
                  const SizedBox(width: AppSpacing.sm),
                  _RoundButton(
                    icon: LucideIcons.externalLink,
                    onScene: widget.onScene,
                    onTap: () => _open(context, music.webUrl),
                  ),
                ],
              ],
            ),
            if (_note(refused: refused, inApp: inApp) case final note?) ...[
              const SizedBox(height: 6),
              Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: widget.onScene
                      ? Colors.white70
                      : context.omColors.text2,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// The line itself: what is playing, and a way to change it.
  Widget _pill(BuildContext context, RoomMusic? music,
      {required bool external}) {
    final c = context.omColors;
    // The same flat, bordered pill family as the session's own controls, so
    // this reads as part of the timer rather than a widget bolted underneath.
    final bg =
        widget.onScene ? Colors.white.withValues(alpha: 0.20) : c.surface;
    final border =
        widget.onScene ? Colors.white.withValues(alpha: 0.32) : c.border;
    final fg = widget.onScene ? Colors.white : c.text;
    final dim = widget.onScene ? Colors.white70 : c.text2;

    return OmTappable(
      feedback: OmTapFeedback.none,
      pressedScale: 0.97,
      onTap: () => _edit(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: ShapeDecoration(
          color: bg,
          shape: StadiumBorder(side: BorderSide(color: border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(music == null ? LucideIcons.plus : LucideIcons.music4,
                size: 17, color: music == null ? dim : fg),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                music?.displayLabel ?? 'add music',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: music == null ? dim : fg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The one line worth saying under the pill, or nothing.
  ///
  /// Silence is the default on purpose: "playing here" under a track that is
  /// audibly playing is noise. This speaks only when something is wrong or
  /// about to surprise someone.
  String? _note({required bool refused, required bool inApp}) {
    if (widget.error != null) return widget.error;
    if (_audioError != null) return _audioError;
    if (refused) return _refusalReason;
    if (widget.music != null && !inApp) {
      return _isRoom
          ? 'everyone opens this in their own Spotify, so you will drift'
          : 'opens in your Spotify app';
    }
    return null;
  }

  Future<void> _open(BuildContext context, Uri url) async {
    Haptics.light();
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      Toast.show(context, "couldn't open that link");
    }
  }

  Future<void> _edit(BuildContext context) async {
    Haptics.light();
    final c = context.omColors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _MusicLinkSheet(
        hasMusic: widget.music != null,
        error: widget.error,
        onSet: widget.onSet,
      ),
    );
  }
}

/// A 44x44 hit area around a small glyph.
///
/// The icons here started at 17px with 6px of padding, which is a 29px target -
/// well under the 44pt minimum, and the wrong place to be stingy in an app
/// whose users are the ones least served by fiddly controls.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.onScene = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool onScene;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final bg = onScene ? Colors.white.withValues(alpha: 0.20) : c.surface;
    final border = onScene ? Colors.white.withValues(alpha: 0.32) : c.border;
    final fg = onScene ? Colors.white : c.text;
    return OmTappable(
      feedback: OmTapFeedback.none,
      pressedScale: 0.94,
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: ShapeDecoration(
          color: bg,
          shape: CircleBorder(side: BorderSide(color: border)),
        ),
        child: Icon(icon, size: 18, color: fg),
      ),
    );
  }
}

/// The paste sheet owns its own controller.
///
/// It used to be a local in _edit, disposed as soon as showModalBottomSheet's
/// future returned - which is before the TextField has unmounted, so Flutter
/// asserted `_dependents.isEmpty` and the whole session screen went red. A
/// StatefulWidget disposes at the right moment by construction.
class _MusicLinkSheet extends StatefulWidget {
  const _MusicLinkSheet({
    required this.hasMusic,
    required this.error,
    required this.onSet,
  });

  final bool hasMusic;
  final String? error;
  final ValueChanged<String?> onSet;

  @override
  State<_MusicLinkSheet> createState() => _MusicLinkSheetState();
}

class _MusicLinkSheetState extends State<_MusicLinkSheet> {
  final _controller = TextEditingController();

  /// Errors from picking, kept apart from the paste field's own error.
  String? _pickError;

  /// Live feedback while typing, so a wrong paste is obvious before submitting.
  MusicLink? get _preview => parseMusicLink(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    widget.onSet(value);
    Navigator.of(context).pop();
  }

  Future<void> _pickFile() async {
    Haptics.light();
    try {
      final picked = await FilePicker.pickFile(type: FileType.audio);
      final path = picked?.path;
      if (path == null) return; // cancelled
      final link = musicLinkForFile(path);
      if (link == null) {
        if (mounted) {
          setState(() => _pickError = 'that file is not audio we can play');
        }
        return;
      }
      if (!mounted) return;
      _submit(link.uri);
    } catch (e) {
      debugPrint('[focus-music] file pick failed: $e');
      if (mounted) setState(() => _pickError = "couldn't open the file picker");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final preview = _preview;

    return Padding(
      // The keyboard inset, or the field sits under it on a short screen.
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('what should play?',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'an audio link or a file on this device plays here. a YouTube '
            'link plays here too, sound only. a Spotify link opens in Spotify.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'paste an audio, YouTube or Spotify link',
              errorText: widget.error ?? _pickError,
              filled: true,
              fillColor: c.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: _submit,
          ),
          if (preview != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  switch (preview.provider) {
                    MusicProvider.stream ||
                    MusicProvider.file =>
                      LucideIcons.audioLines,
                    MusicProvider.youtube => LucideIcons.play,
                    MusicProvider.spotify => LucideIcons.externalLink,
                  },
                  size: 14,
                  color: c.text2,
                ),
                const SizedBox(width: 6),
                Text(
                  switch (preview.provider) {
                    MusicProvider.stream ||
                    MusicProvider.file =>
                      'plays here as audio, no video',
                    MusicProvider.youtube => 'plays here as audio',
                    MusicProvider.spotify => 'opens in Spotify',
                  },
                  style: TextStyle(fontSize: 12, color: c.text2),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          // The one source that always works: music this phone already holds.
          // No link to find, no provider to satisfy, nothing to go wrong on a
          // train with no signal.
          OmTappable(
            onTap: _pickFile,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(LucideIcons.folderOpen, size: 16, color: c.text2),
                  const SizedBox(width: 8),
                  Text('or choose a file on this device',
                      style: TextStyle(fontSize: 13, color: c.text2)),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              if (widget.hasMusic)
                TextButton(
                  onPressed: () {
                    widget.onSet(null);
                    Navigator.of(context).pop();
                  },
                  child: const Text('stop'),
                ),
              const Spacer(),
              FilledButton(
                onPressed: () => _submit(_controller.text),
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('set it'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
