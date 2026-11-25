import 'dart:async';

import 'package:audioplayers/audioplayers.dart' as ap;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/pro_features.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/services/api_client.dart';
import '../../../core/utils/music_link.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/music_playback.dart';
import '../../../core/utils/toast.dart';
import '../../../providers/premium_provider.dart';
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
///   Searched tracks, direct audio links and files on the device all play
///   HERE, out of Mynd.
///
///   YouTube and Spotify are handed to their own apps. Spotify cannot be
///   embedded on mobile at all, and YouTube's API Terms require their player
///   to stay visible and unobscured, which a focus timer has nowhere to put.
///   Both degrade honestly to a hand-off, and the line says so instead of
///   letting someone find out by pressing play.
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
  ///
  /// [title] is passed when we already know what the track is called - a
  /// search result knows, a pasted URL does not - so the bar does not have to
  /// fall back to guessing a name out of the last path segment.
  final void Function(String? raw, {String? title}) onSet;

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

class _MusicBarState extends State<MusicBar> {
  /// What the controller currently holds, so an unrelated rebuild does not
  /// reload the track and restart it from zero.
  String? _loadedUri;

  /// The last play/pause we asked for, so the desired state is only ever
  /// asserted on a change. Re-asserting it on every rebuild is how music came
  /// back on underneath a paused timer.
  bool? _commandedPlay;

  Timer? _drift;

  Duration _duration = Duration.zero;

  /// The engine. Audio only, which is the whole of what this bar will play.
  ap.AudioPlayer? _audio;
  final List<StreamSubscription<dynamic>> _audioSubs = [];
  String? _audioError;

  bool get _isRoom => widget.onPausedChanged != null;

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

    // Nothing playable here: stop and let go of the engine rather than leaving
    // it parked holding a track nobody is listening to.
    if (music == null || link == null || !music.playsInApp) {
      _disposeAudio();
      _drift?.cancel();
      _drift = null;
      _loadedUri = null;
      _commandedPlay = null;
      _duration = Duration.zero;
      return;
    }

    if (_loadedUri == music.uri) {
      _applyDesiredPlayback();
      return;
    }
    _loadedUri = music.uri;
    // A new track gets a clean slate, or the previous one's length would be
    // used to wrap this one's playhead.
    _duration = Duration.zero;

    // Where the room already is, not the beginning. Someone joining twenty
    // minutes in hears what everybody else hears.
    final at = music.positionAt(DateTime.now());
    final shouldPlay = widget.sessionRunning && !music.paused;
    _commandedPlay = shouldPlay;

    // Seek only where there is a room clock to line up with. Solo has none,
    // and seeking to a room position that does not exist is how the audio
    // ended up starting past the end of the track.
    _loadAudio(link, play: shouldPlay, at: _isRoom ? at : null);
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
    if (audio == null) return;
    play ? audio.resume() : audio.pause();
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
      final audio = _audio;
      if (music == null || audio == null || music.paused || !mounted) return;
      try {
        final actual = await audio.getCurrentPosition();
        if (actual == null) return;
        // Wrapped by the track length, because the room's playhead keeps
        // counting up across repeats while the engine loops back to zero.
        // Without this, the first loop would put the target past the end of
        // the track and every device would be yanked to a position that does
        // not exist.
        final target =
            loopedPosition(music.positionAt(DateTime.now()), _duration);
        if ((actual - target).abs() > const Duration(seconds: 4)) {
          await audio.seek(target);
        }
      } catch (_) {
        // The engine can be torn down mid-await. Drift correction is a nicety.
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final music = widget.music;
    final inApp = music != null && music.playsInApp;
    // Anything we cannot play ourselves is handed to the app that owns it.
    final external = music != null && !inApp;

    return Stack(
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                // A room needs its own pause, because a room has no shared
                // timer to inherit one from: each person's clock is their own,
                // so the music is the only thing everybody is actually on.
                if (_isRoom && inApp) ...[
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
            if (_note(inApp: inApp) case final note?) ...[
              const SizedBox(height: 6),
              Text(
                note,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      widget.onScene ? Colors.white70 : context.omColors.text2,
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
                _label(music),
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

  /// What to call the track.
  ///
  /// The stored title first, because that is the one a room agrees on and the
  /// one that survives a restart. The id-based label is the last resort.
  String _label(RoomMusic? music) {
    if (music == null) return 'add music';
    final stored = music.title;
    if (stored != null && stored.isNotEmpty) return stored;
    return music.displayLabel;
  }

  /// The one line worth saying under the pill, or nothing.
  ///
  /// Silence is the default on purpose: "playing here" under a track that is
  /// audibly playing is noise. This speaks only when something is wrong or
  /// about to surprise someone.
  String? _note({required bool inApp}) {
    if (widget.error != null) return widget.error;
    if (_audioError != null) return _audioError;
    if (widget.music != null && !inApp) {
      // A hand-off cannot be kept in step: the other app has its own transport
      // and nobody here can see where it got to.
      return _isRoom
          ? 'everyone opens this in their own app, so you will drift'
          : 'opens in its own app';
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
  final void Function(String? raw, {String? title}) onSet;

  @override
  State<_MusicLinkSheet> createState() => _MusicLinkSheetState();
}

class _MusicLinkSheetState extends State<_MusicLinkSheet> {
  /// Whether music from the internet is out of reach on this plan.
  ///
  /// Read from the provider each build rather than captured once, so that
  /// subscribing and coming back to this sheet shows the field rather than
  /// the upsell.
  bool get _streamLocked => !ProFeatures.canStreamMusic(
      premium: context.watch<PremiumProvider>().isPremium);

  final _controller = TextEditingController();

  /// Errors from picking, kept apart from the paste field's own error.
  String? _pickError;

  /// A search in flight, and anything that went wrong with the last one.
  bool _searching = false;
  String? _searchError;

  /// Live feedback while typing, so a wrong paste is obvious before submitting.
  MusicLink? get _preview => parseMusicLink(_controller.text);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Typing a name searches; pasting a link still just works.
  ///
  /// The two are told apart by whether the text parses as a link we recognise,
  /// not by looking for "http" - somebody typing a band with a dot in its name
  /// should still get a search, and a bare youtu.be/xxxx with no scheme should
  /// still be treated as the link it obviously is.
  Future<void> _submit(String value) async {
    final raw = value.trim();
    if (raw.isEmpty) return;

    if (parseMusicLink(raw) != null) {
      widget.onSet(raw);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final results = await ApiClient.instance.searchMusic(raw);
      if (!mounted) return;
      if (results.isEmpty) {
        setState(() {
          _searching = false;
          _searchError = 'nothing found for "$raw"';
        });
        return;
      }
      // Best match, played. Its name goes up with it, so if the match is wrong
      // that is obvious immediately rather than after a minute of listening.
      final best = results.first;
      widget.onSet(best.url, title: best.label);
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _searching = false;
        _searchError = 'could not search just now';
      });
    }
  }

  void _submitRaw(String value) {
    unawaited(_submit(value));
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
      _submitRaw(link.uri);
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
            _streamLocked
                ? 'play a track from this device on any plan. searching for '
                    'music and pasting links are part of Pro.'
                : 'type what you want to hear and the closest match plays. or '
                    'paste a link: an audio link plays here, while YouTube and '
                    'Spotify open in their own apps.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          // The search field is the whole of "music from the internet", so it
          // is the thing that is gated. The file picker below stays open on
          // every plan: a focus timer that cannot play anything at all would
          // be a worse free tier than the one that exists today, and this is
          // meant to add a reason to upgrade rather than take something away.
          if (_streamLocked)
            OmTappable(
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(AppRoutes.paywall);
              },
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                  border: Border.all(color: c.primary.withValues(alpha: 0.35)),
                ),
                child: Row(
                  children: [
                    Icon(OmIcons.byName('lock'), size: 16, color: c.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Search any track with Pro',
                        style: TextStyle(
                            color: c.primary, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'a song name, or paste a link',
                errorText: widget.error ?? _pickError ?? _searchError,
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                filled: true,
                fillColor: c.surfaceAlt,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: _submitRaw,
            ),
          if (!_streamLocked) ...[
            const SizedBox(height: 6),
            // Named, because the catalogue is somebody else's work and
            // Audius's API is offered on the understanding that apps using it
            // say so. The per-track artist credit is in MusicSearchResult's
            // label; this is the platform half of the same courtesy, and it
            // also stops "search" reading as a promise of every song ever
            // recorded.
            Text(
              'Results come from Audius, an open music platform. '
              'Tracks are credited to their artists.',
              style: TextStyle(fontSize: 11, color: c.text2, height: 1.4),
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Icon(
                  switch (preview.provider) {
                    MusicProvider.stream ||
                    MusicProvider.file =>
                      LucideIcons.audioLines,
                    MusicProvider.youtube => LucideIcons.externalLink,
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
                    // Not "plays here as audio", which is what this said and
                    // is the one thing it must never say. playsInApp is false
                    // for YouTube and the link is handed to the YouTube app,
                    // because their API Terms require their player to stay
                    // visible. The old line advertised audio-only YouTube
                    // playback - a 5.2.3 rejection for a thing the app does
                    // not even do.
                    MusicProvider.youtube => 'opens in YouTube',
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
