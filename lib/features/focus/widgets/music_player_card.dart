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
import '../../../widgets/om_card.dart';
import '../../../widgets/om_tappable.dart';
import 'music_disc.dart';

/// The music surface for a focus session, solo or shared.
///
/// Two providers, two very different capabilities, one card:
///
///   YouTube plays HERE. The IFrame player is embedded in the card, so the
///   audio comes out of Mynd and a room can line up on the same position.
///
///   Spotify cannot play here and never will on mobile. Their Web Playback SDK
///   needs EME/Widevine and is unsupported in a webview; the App Remote SDK is
///   a remote control for the Spotify app, not a source of audio. So a Spotify
///   link degrades honestly to a hand-off, and the card says which one you are
///   getting rather than letting someone discover it by pressing play.
///
/// The player is deliberately VISIBLE. Sizing the iframe to zero, or parking it
/// off-screen to fake an audio-only player, is the specific thing YouTube's API
/// Terms prohibit, and it is what gets an app pulled. A visible player is also
/// the only way the viewer sees what is playing, which is the point.
class MusicPlayerCard extends StatefulWidget {
  const MusicPlayerCard({
    super.key,
    required this.music,
    required this.onSet,
    required this.emptyHint,
    required this.handOffNote,
    this.onPausedChanged,
    this.error,
    this.sessionRunning = true,
  });

  final RoomMusic? music;

  /// Called with a raw pasted string, or null to stop.
  final ValueChanged<String?> onSet;

  /// Shown when nothing is playing.
  final String emptyHint;

  /// The one-liner explaining a Spotify link's hand-off, which differs between
  /// a room (everyone drifts) and a solo session (it just leaves the app).
  final String handOffNote;

  /// Pause/resume for everyone. Null in a solo session, where pausing is a
  /// local matter and there is nobody to sync with.
  final ValueChanged<bool>? onPausedChanged;

  final String? error;

  /// Whether the focus timer itself is running.
  ///
  /// Music follows the session: pausing the timer to take a call should not
  /// leave the track playing, and resuming should bring it back without a
  /// second tap. Rooms pass true and use their own room-wide pause instead,
  /// because there the timer is server-driven and shared.
  final bool sessionRunning;

  @override
  State<MusicPlayerCard> createState() => _MusicPlayerCardState();
}

/// The disc, and therefore the hidden player behind it, are this wide.
const double _discSize = 188;

class _MusicPlayerCardState extends State<MusicPlayerCard> {
  YoutubePlayerController? _yt;
  StreamSubscription<YoutubePlayerValue>? _sub;

  /// What the controller currently holds, so an unrelated rebuild does not
  /// reload the video and restart it from zero.
  String? _loadedUri;

  Timer? _drift;

  YoutubeError _ytError = YoutubeError.none;
  PlayerState _state = PlayerState.unknown;

  /// Set when the listener paused the music by hand.
  ///
  /// Kept so that following the session cannot undo a deliberate choice: if
  /// someone silenced the track and then paused and resumed the timer, the
  /// music should stay silent rather than come back on its own.
  bool _pausedByHand = false;

  /// The audio-only engine, used for direct stream URLs.
  ///
  /// Separate from the YouTube controller rather than hidden behind one
  /// interface, because they differ in the way that matters: this one has no
  /// picture and no terms attached to showing one.
  ap.AudioPlayer? _audio;
  final List<StreamSubscription<dynamic>> _audioSubs = [];
  bool _audioPlaying = false;
  String? _audioError;

  StreamSubscription<YoutubeVideoState>? _posSub;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  /// Elapsed fraction for the ring, or null while the duration is unknown.
  double? get _progress => _duration.inMilliseconds <= 0
      ? null
      : _position.inMilliseconds / _duration.inMilliseconds;

  bool get _isRoom => widget.onPausedChanged != null;

  /// Whether YouTube refused this video outright, as opposed to still loading.
  ///
  /// Worth its own state because it is common and silent: a large share of
  /// popular music videos, and most 24/7 study streams, are marked
  /// "not embeddable" by their uploader. Without this the card just sits blank
  /// forever and looks broken, when in fact the app is working and the video is
  /// refusing.
  bool get _refused => switch (_ytError) {
        YoutubeError.notEmbeddable ||
        YoutubeError.sameAsNotEmbeddable ||
        YoutubeError.sameAsNotEmbeddable2 =>
          true,
        YoutubeError.videoNotFound ||
        YoutubeError.cannotFindVideo ||
        YoutubeError.invalidParam ||
        YoutubeError.html5Error =>
          true,
        _ => false,
      };

  String get _refusalReason => switch (_ytError) {
        YoutubeError.notEmbeddable ||
        YoutubeError.sameAsNotEmbeddable ||
        YoutubeError.sameAsNotEmbeddable2 =>
          "the uploader doesn't allow this one to play outside YouTube",
        YoutubeError.videoNotFound || YoutubeError.cannotFindVideo =>
          'that video is private or gone',
        _ => "that video won't play here",
      };

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MusicPlayerCard old) {
    super.didUpdateWidget(old);
    _sync();
    // Only on the edge, never on every rebuild: reasserting the desired state
    // continuously would override the listener's own play/pause a frame after
    // they pressed it.
    if (old.sessionRunning != widget.sessionRunning) _followSession();
  }

  /// Pause with the timer, and come back with it.
  void _followSession() {
    final audio = _audio;
    if (audio != null) {
      if (!widget.sessionRunning) {
        audio.pause();
        return;
      }
      if (_pausedByHand || (widget.music?.paused ?? false)) return;
      audio.resume();
      return;
    }
    final yt = _yt;
    if (yt == null || _refused) return;
    if (!widget.sessionRunning) {
      _quietly(yt.pauseVideo);
      return;
    }
    // A hand-paused track stays paused, and so does one the room has stopped.
    if (_pausedByHand || (widget.music?.paused ?? false)) return;
    _quietly(yt.playVideo);
  }

  @override
  void dispose() {
    _drift?.cancel();
    _sub?.cancel();
    _posSub?.cancel();
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
      _audioSubs.addAll([
        player.onPositionChanged.listen((d) {
          if (!mounted || d.inSeconds == _position.inSeconds) return;
          setState(() => _position = d);
        }),
        player.onDurationChanged.listen((d) {
          if (!mounted || d == _duration) return;
          setState(() => _duration = d);
        }),
        player.onPlayerStateChanged.listen((st) {
          if (!mounted) return;
          setState(() => _audioPlaying = st == ap.PlayerState.playing);
        }),
      ]);
    }
    try {
      // Playback category, so audio keeps going when the phone is locked and
      // mixes politely rather than stopping whatever else is playing.
      await player.setAudioContext(ap.AudioContextConfig(
        focus: ap.AudioContextConfigFocus.mixWithOthers,
      ).build());
      // A device file is read straight off disk; a stream is fetched. Same
      // engine either way, so everything downstream is identical.
      final path = link.filePath;
      // The engine repeats it for us, so there is no gap and no state to keep.
      await player.setReleaseMode(ap.ReleaseMode.loop);
      await player.setSource(
          path != null ? ap.DeviceFileSource(path) : ap.UrlSource(link.streamUrl!));
      if (at != null && at > Duration.zero) await player.seek(at);
      if (play) {
        await player.resume();
      }
      if (mounted && _audioError != null) setState(() => _audioError = null);
    } catch (e) {
      debugPrint('[focus-music] audio load failed: $e');
      if (mounted) {
        setState(() => _audioError = link.filePath != null
            ? "that file would not play"
            : "that audio link would not play");
      }
    }
  }

  /// Bring the embedded player in line with what the session says is playing.
  void _sync() {
    final music = widget.music;
    final link = music?.link;

    // Nothing playable in-app: tear the webview down rather than leaving it
    // parked. It is the most expensive thing on this screen.
    if (music == null || link == null || !music.playsInApp) {
      _disposeAudio();
      if (_yt != null) {
        _drift?.cancel();
        _drift = null;
        _sub?.cancel();
        _sub = null;
        _posSub?.cancel();
        _posSub = null;
        _yt?.close();
        _yt = null;
        _loadedUri = null;
        _ytError = YoutubeError.none;
        _state = PlayerState.unknown;
      }
      return;
    }

    if (_loadedUri == music.uri) {
      // Same track: react only to the room stopping it. Reasserting "play"
      // here would mean every unrelated rebuild overrode a local pause.
      if (!music.paused) return;
      if (link.audioOnly) {
        _audio?.pause();
      } else {
        _quietly(_yt!.pauseVideo);
      }
      return;
    }
    _loadedUri = music.uri;
    // A new track gets a clean slate, or the previous video's refusal would
    // hide a working one - and choosing a track is itself a request to hear
    // it, so a previous hand-pause does not carry over.
    _ytError = YoutubeError.none;
    _state = PlayerState.unknown;
    _pausedByHand = false;
    _position = Duration.zero;
    _duration = Duration.zero;

    // Where the room already is, not the beginning. Someone joining twenty
    // minutes in hears what everybody else hears.
    final at = music.positionAt(DateTime.now());
    final start = at.inSeconds.toDouble();
    final shouldPlay = widget.sessionRunning && !music.paused;

    // A direct audio URL has no picture and needs no webview. This is the only
    // path that is genuinely audio-only.
    if (link.audioOnly) {
      _yt?.close();
      _yt = null;
      // Seek only where there is a room clock to line up with. Solo has none,
      // and seeking to a room position that does not exist is how the audio
      // ended up starting past the end of the track.
      _loadAudio(link, play: shouldPlay, at: _isRoom ? at : null);
      _startDriftCorrection();
      return;
    }

    if (_yt == null) {
      _yt = YoutubePlayerController(
        params: const YoutubePlayerParams(
          // The player is for watching, not operating. Its own controls are
          // hidden and it ignores pointer events entirely, because a WKWebView
          // sitting in a scrolling column swallows vertical drags: a swipe that
          // began on the player would not scroll the session screen. The card
          // supplies its own play/pause below instead.
          showControls: false,
          pointerEvents: PointerEvents.none,
          showFullscreenButton: false,
          playsInline: true,
          // Do not trail unrelated videos after a focus track ends.
          strictRelatedVideos: true,
          // youtube-nocookie.com: no cookie is set unless playback starts.
          privacyEnhancedMode: true,
          // Repeat rather than fall silent. This flag is what wraps a
          // playlist round to its first video; a single video is handled by
          // _loopAgain below, because the IFrame API only honours loop for a
          // lone video when it was given as a one-item playlist, which is not
          // how loadVideoById works.
          loop: true,
        ),
      );
      _sub = _yt!.stream.listen((v) {
        if (!mounted) return;
        final d = v.metaData.duration;
        // Only the transition into ended, never the state sitting there: the
        // stream re-emits whenever anything on the value changes, and
        // restarting on each of those would fight the seek.
        final justEnded =
            v.playerState == PlayerState.ended && _state != PlayerState.ended;
        if (v.error != _ytError || v.playerState != _state || d != _duration) {
          setState(() {
            _ytError = v.error;
            _state = v.playerState;
            _duration = d;
          });
        }
        if (justEnded) _loopAgain();
      });
      _posSub = _yt!.videoStateStream.listen((v) {
        // Only when it moves a whole second: the player reports every 100ms,
        // and repainting the ring ten times a second on a screen nobody is
        // watching is battery spent for nothing.
        if (!mounted || v.position.inSeconds == _position.inSeconds) return;
        setState(() => _position = v.position);
      });
    }

    // load* autoplays, cue* only prepares. Choosing between them is what
    // makes a fresh mount respect a paused session: switching the scene wraps
    // the screen in a Stack, which rebuilds this card from scratch, and a
    // plain load would restart the music underneath a paused timer.
    _quietly(() => switch (playerLoadAction(
          isPlaylist: link.kind == 'playlist',
          sessionRunning: widget.sessionRunning,
          roomPaused: music.paused,
        )) {
          PlayerLoadAction.loadPlaylist => _yt!.loadPlaylist(
              list: [link.id],
              listType: ListType.playlist,
              startSeconds: start,
            ),
          PlayerLoadAction.cuePlaylist => _yt!.cuePlaylist(
              list: [link.id],
              listType: ListType.playlist,
              startSeconds: start,
            ),
          PlayerLoadAction.loadVideo =>
            _yt!.loadVideoById(videoId: link.id, startSeconds: start),
          PlayerLoadAction.cueVideo =>
            _yt!.cueVideoById(videoId: link.id, startSeconds: start),
        });

    _startDriftCorrection();
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
    // normally reach the end while paused, but a race between the room's stop
    // and the last second of a track should not restart it.
    if (!widget.sessionRunning || _pausedByHand) return;
    if (widget.music?.paused ?? false) return;
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

  bool get _playing =>
      _audio != null ? _audioPlaying : _state == PlayerState.playing;

  void _togglePlay() {
    Haptics.light();
    final onPaused = widget.onPausedChanged;
    if (onPaused != null) {
      // The room's pause: the server owns the playhead, so state the intent and
      // wait for it to come back as music_changed.
      onPaused(!(widget.music?.paused ?? false));
      return;
    }
    _pausedByHand = _playing;
    final audio = _audio;
    if (audio != null) {
      _playing ? audio.pause() : audio.resume();
      return;
    }
    final yt = _yt;
    if (yt == null) return;
    _quietly(_playing ? yt.pauseVideo : yt.playVideo);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final music = widget.music;
    final link = music?.link;
    final audioOnly = link?.audioOnly ?? false;
    final inApp = music != null && music.playsInApp && (_yt != null || audioOnly);
    final refused = inApp && !audioOnly && _refused;

    final content = Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (refused)
              _Refusal(reason: _refusalReason, url: music.webUrl)
            else
              SizedBox(
                width: _discSize,
                height: _discSize,
                child: Stack(
                  // Clips the player out of sight. Not decoration: see below.
                  clipBehavior: Clip.hardEdge,
                  alignment: Alignment.center,
                  children: [
                    // The YouTube player, kept mounted and playing but moved
                    // outside the clip so nothing of it is seen.
                    //
                    // Laid out at full size and merely displaced, rather than
                    // sized to zero as the usual recipe suggests: iOS
                    // throttles or suspends media in a webview with no area,
                    // so a 0x0 player is a player that stops playing. Painting
                    // an opaque layer over it does not work either - iOS
                    // composites a WKWebView in the native hierarchy, above
                    // Flutter's own content, so the cover was simply invisible.
                    //
                    // This is a deliberate departure from YouTube's API Terms,
                    // which require the embedded player to stay visible and
                    // unobscured. Anj asked for it explicitly and repeatedly,
                    // knowing the consequence: App Review can reject the build
                    // and YouTube can revoke API access. Confined to this one
                    // block so it is the first thing to undo if either
                    // happens.
                    if (inApp && !audioOnly)
                      Positioned(
                        left: -_discSize * 4,
                        top: 0,
                        width: _discSize,
                        height: _discSize,
                        child: IgnorePointer(
                          child: YoutubePlayer(
                            controller: _yt!,
                            aspectRatio: 1,
                            enableFullScreenOnVerticalDrag: false,
                            autoFullScreen: false,
                          ),
                        ),
                      ),
                    MusicDisc(
                      artworkUrl: music?.link?.artworkUrl,
                      playing: _showAsPlaying,
                      progress: _progress,
                      size: _discSize,
                    ),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              music?.displayLabel ?? 'nothing playing',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: music == null ? c.text2 : c.text,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              _caption(refused: refused, inApp: inApp),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: c.text2),
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (music != null && !inApp)
                  _IconButton(
                    icon: LucideIcons.externalLink,
                    color: c.primary,
                    onTap: () => _open(context, music.webUrl),
                  ),
                if (inApp && !refused) _PlayButton(
                  playing: _showAsPlaying,
                  onTap: _togglePlay,
                ),
                _IconButton(
                  icon: LucideIcons.pencil,
                  color: c.text2,
                  onTap: () => _edit(context),
                ),
              ],
            ),
          ],
        ),
      );

    return OmCard(child: content);
  }

  /// True when the card should look like it is playing.
  ///
  /// In a room that is the room's flag, so every screen agrees even before the
  /// local player has caught up; solo it is the player's own state.
  bool get _showAsPlaying =>
      _isRoom ? !(widget.music?.paused ?? true) : _playing;

  String _caption({required bool refused, required bool inApp}) {
    if (widget.music == null) return widget.emptyHint;
    if (_audioError != null) return _audioError!;
    if (refused) return 'not playing';
    if (!inApp) return widget.handOffNote;
    return widget.sessionRunning ? 'playing here' : 'paused with your session';
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

/// Shown in place of the player when YouTube refuses the video.
///
/// A large share of music videos, and most 24/7 study streams, are marked
/// not-embeddable by their uploader. That is invisible from the link, so the
/// only honest thing is to say what happened and offer the one route that does
/// work: open it on YouTube.
class _Refusal extends StatelessWidget {
  const _Refusal({required this.reason, required this.url});

  final String reason;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.lg, AppSpacing.md, 0),
      child: Column(
        children: [
          Icon(LucideIcons.videoOff, size: 22, color: c.text2),
          const SizedBox(height: AppSpacing.sm),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: c.text2),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton.icon(
            onPressed: () async {
              Haptics.light();
              final ok =
                  await launchUrl(url, mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                Toast.show(context, "couldn't open YouTube");
              }
            },
            icon: const Icon(LucideIcons.externalLink, size: 15),
            label: const Text('open on YouTube'),
          ),
        ],
      ),
    );
  }
}


/// The primary transport control.
///
/// Deliberately the largest thing under the disc: it is the one control anyone
/// reaches for mid-session, and a focus app is the wrong place to make someone
/// aim at a 17px glyph.
class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, required this.onTap});

  final bool playing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.primary),
        child: Icon(
          playing ? LucideIcons.pause : LucideIcons.play,
          size: 22,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// A 44x44 hit area around a small glyph.
///
/// The icons here were 17px with 6px of padding, which is a 29px target - well
/// under the 44pt minimum, and the wrong place to be stingy in an app whose
/// users are the ones least served by fiddly controls.
class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OmTappable(
      onTap: onTap,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Icon(icon, size: 18, color: color),
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
        if (mounted) setState(() => _pickError = "that file is not audio we can play");
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
