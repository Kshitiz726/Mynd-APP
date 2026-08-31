import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/music_link.dart';
import '../../../core/utils/toast.dart';
import '../../../models/room_music.dart';
import '../../../widgets/om_card.dart';
import '../../../widgets/om_tappable.dart';

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

  @override
  State<MusicPlayerCard> createState() => _MusicPlayerCardState();
}

class _MusicPlayerCardState extends State<MusicPlayerCard> {
  YoutubePlayerController? _yt;
  StreamSubscription<YoutubePlayerValue>? _sub;

  /// What the controller currently holds, so an unrelated rebuild does not
  /// reload the video and restart it from zero.
  String? _loadedUri;

  Timer? _drift;

  YoutubeError _ytError = YoutubeError.none;
  PlayerState _state = PlayerState.unknown;

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
  }

  @override
  void dispose() {
    _drift?.cancel();
    _sub?.cancel();
    _yt?.close();
    super.dispose();
  }

  /// Bring the embedded player in line with what the session says is playing.
  void _sync() {
    final music = widget.music;
    final link = music?.link;

    // Nothing playable in-app: tear the webview down rather than leaving it
    // parked. It is the most expensive thing on this screen.
    if (music == null || link == null || !music.playsInApp) {
      if (_yt != null) {
        _drift?.cancel();
        _drift = null;
        _sub?.cancel();
        _sub = null;
        _yt?.close();
        _yt = null;
        _loadedUri = null;
        _ytError = YoutubeError.none;
        _state = PlayerState.unknown;
      }
      return;
    }

    if (_loadedUri == music.uri) {
      _applyPlayState(music);
      return;
    }
    _loadedUri = music.uri;
    // A new track gets a clean slate, or the previous video's refusal would
    // hide a working one.
    _ytError = YoutubeError.none;
    _state = PlayerState.unknown;

    // Where the room already is, not the beginning. Someone joining twenty
    // minutes in hears what everybody else hears.
    final start = music.positionAt(DateTime.now()).inSeconds.toDouble();

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
        ),
      );
      _sub = _yt!.stream.listen((v) {
        if (!mounted) return;
        if (v.error != _ytError || v.playerState != _state) {
          setState(() {
            _ytError = v.error;
            _state = v.playerState;
          });
        }
      });
    }

    _quietly(() => link.kind == 'playlist'
        ? _yt!.loadPlaylist(
            list: [link.id],
            listType: ListType.playlist,
            startSeconds: start,
          )
        : _yt!.loadVideoById(videoId: link.id, startSeconds: start));

    _applyPlayState(music);
    _startDriftCorrection();
  }

  void _applyPlayState(RoomMusic music) {
    final yt = _yt;
    if (yt == null) return;
    // A room-wide pause is a real instruction; a solo session pauses locally,
    // so `paused` is always false there and this is a no-op.
    if (music.paused) _quietly(yt.pauseVideo);
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
        final target = music.positionAt(DateTime.now()).inSeconds.toDouble();
        if ((actual - target).abs() > 4) {
          await yt.seekTo(seconds: target, allowSeekAhead: true);
        }
      } catch (_) {
        // The webview can be gone mid-await. Drift correction is a nicety.
      }
    });
  }

  bool get _playing => _state == PlayerState.playing;

  void _togglePlay() {
    Haptics.light();
    final onPaused = widget.onPausedChanged;
    if (onPaused != null) {
      // The room's pause: the server owns the playhead, so state the intent and
      // wait for it to come back as music_changed.
      onPaused(!(widget.music?.paused ?? false));
      return;
    }
    final yt = _yt;
    if (yt == null) return;
    _quietly(_playing ? yt.pauseVideo : yt.playVideo);
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.music;
    final inApp = music != null && music.playsInApp && _yt != null;

    return OmCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (inApp && _refused)
            _Refusal(reason: _refusalReason, url: music.webUrl)
          else if (inApp)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
              // The player is display-only: every control belongs to the card,
              // so nothing here should react to a touch. This kills accidental
              // taps landing on the video.
              //
              // It does NOT make the card scrollable. Measured on an iPhone 15
              // simulator: a swipe starting on the player still scrolls
              // nothing, while the same swipe a few points higher scrolls
              // normally. The WKWebView intercepts the touch in the native view
              // hierarchy, below the level Flutter's hit testing reaches, so
              // neither this nor `pointerEvents: none` hands the drag back.
              // Left as a known rough edge rather than papered over with a
              // transparent drag-forwarding overlay, which would fight the
              // scroll physics for a gesture users can make anywhere else on
              // the screen.
              child: IgnorePointer(
                child: YoutubePlayer(
                  controller: _yt!,
                  aspectRatio: 16 / 9,
                  enableFullScreenOnVerticalDrag: false,
                  autoFullScreen: false,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: _Row(
              music: music,
              emptyHint: widget.emptyHint,
              handOffNote: widget.handOffNote,
              // Nothing to play or pause while the video is being refused.
              onTogglePlay: inApp && !_refused ? _togglePlay : null,
              // "playing here" would be a lie while the panel above it is
              // explaining that it will not play at all.
              refused: inApp && _refused,
              showAsPlaying: _isRoom ? !(music?.paused ?? true) : _playing,
              onEdit: () => _edit(context),
            ),
          ),
        ],
      ),
    );
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

/// The title line and the controls, below the player.
class _Row extends StatelessWidget {
  const _Row({
    required this.music,
    required this.emptyHint,
    required this.handOffNote,
    required this.onTogglePlay,
    required this.showAsPlaying,
    required this.refused,
    required this.onEdit,
  });

  final RoomMusic? music;
  final String emptyHint;
  final String handOffNote;
  final VoidCallback? onTogglePlay;
  final bool showAsPlaying;
  final bool refused;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final m = music;
    final inApp = m?.playsInApp ?? false;

    return Row(
      children: [
        if (!inApp) ...[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: m == null ? c.surfaceAlt : c.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              m == null ? LucideIcons.music : LucideIcons.music4,
              size: 18,
              color: m == null ? c.text2 : c.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                m?.displayLabel ?? 'nothing playing',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: m == null ? c.text2 : c.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                m == null
                    ? emptyHint
                    : refused
                        ? 'not playing'
                        : (inApp ? 'playing here' : handOffNote),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: c.text2),
              ),
            ],
          ),
        ),
        if (onTogglePlay != null)
          _IconButton(
            icon: showAsPlaying ? LucideIcons.pause : LucideIcons.play,
            color: c.primary,
            onTap: onTogglePlay!,
          ),
        // Spotify is the only case that leaves the app, so it is the only case
        // that gets a launch button.
        if (m != null && !inApp)
          _IconButton(
            icon: LucideIcons.externalLink,
            color: c.primary,
            onTap: () async {
              Haptics.light();
              final ok = await launchUrl(m.webUrl,
                  mode: LaunchMode.externalApplication);
              if (!ok && context.mounted) {
                Toast.show(context, "couldn't open that link");
              }
            },
          ),
        _IconButton(icon: LucideIcons.pencil, color: c.text2, onTap: onEdit),
      ],
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
            'a YouTube link plays right here. a Spotify link opens in Spotify, '
            'because Spotify cannot play inside another app.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'https://youtube.com/watch?v=...',
              errorText: widget.error,
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
                  preview.playsInApp
                      ? LucideIcons.play
                      : LucideIcons.externalLink,
                  size: 14,
                  color: c.text2,
                ),
                const SizedBox(width: 6),
                Text(
                  preview.playsInApp ? 'plays in the app' : 'opens in Spotify',
                  style: TextStyle(fontSize: 12, color: c.text2),
                ),
              ],
            ),
          ],
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
