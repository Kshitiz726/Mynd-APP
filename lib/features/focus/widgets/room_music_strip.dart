import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/toast.dart';
import '../../../core/services/focus_music_store.dart';
import '../../../models/room_music.dart';
import '../../../providers/focus_room_provider.dart';
import '../../../widgets/om_card.dart';
import '../../../widgets/om_tappable.dart';

/// What the room is playing, and a way to change it.
///
/// Deliberately a strip and not a player. The room already has a timer and a
/// participant grid competing for attention, and this is the least important of
/// the three: it says what is on, who put it on, and gets out of the way.
///
/// It is honest about what it is. Each person hears this on their own Spotify,
/// so positions drift; the copy says so in one line rather than burying it in a
/// help sheet and letting people discover it by being out of step with a friend.
/// The room's copy: shared state, everyone sees the same thing.
class RoomMusicStrip extends StatelessWidget {
  const RoomMusicStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final room = context.watch<FocusRoomProvider>();
    return MusicStrip(
      music: room.music,
      error: room.musicError,
      onSet: (v) => room.setMusic(v),
      emptyHint: 'paste a Spotify link for the room',
      // Said plainly rather than buried in a help sheet. People WILL notice
      // they are a second or two out from each other, and being told up front
      // is better than discovering it and assuming it is broken.
      subtitle: 'everyone plays this on their own Spotify',
    );
  }
}

/// The solo session's copy: same link handling, stored on the device because
/// there is nobody to agree with.
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
  Widget build(BuildContext context) => MusicStrip(
        music: _store.music,
        error: _store.error,
        onSet: (v) => _store.set(v),
        emptyHint: 'paste a Spotify link to play while you work',
        subtitle: 'plays in your Spotify app',
      );
}

/// The strip itself. Deliberately knows nothing about where the state lives, so
/// the room and a solo session cannot end up accepting different links or
/// describing themselves differently.
class MusicStrip extends StatelessWidget {
  const MusicStrip({
    super.key,
    required this.music,
    required this.onSet,
    required this.emptyHint,
    required this.subtitle,
    this.error,
  });

  final RoomMusic? music;
  final ValueChanged<String?> onSet;
  final String emptyHint;
  final String subtitle;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return OmCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: music == null ? c.surfaceAlt : c.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                music == null ? LucideIcons.music : LucideIcons.music4,
                size: 18,
                color: music == null ? c.text2 : c.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    music?.displayLabel ?? 'nothing playing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: music == null ? c.text2 : c.text,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    music == null ? emptyHint : subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: c.text2),
                  ),
                ],
              ),
            ),
            if (music case final m?)
              OmTappable(
                onTap: () async {
                  Haptics.light();
                  // Hand it to the OS: Spotify claims these links, and if it is
                  // not installed the browser opens the same page rather than
                  // nothing happening.
                  final ok = await launchUrl(m.webUrl,
                      mode: LaunchMode.externalApplication);
                  if (!ok && context.mounted) {
                    Toast.show(context, "couldn't open Spotify");
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(LucideIcons.play, size: 18, color: c.primary),
                ),
              ),
            OmTappable(
              onTap: () => _edit(context),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: Icon(LucideIcons.pencil, size: 17, color: c.text2),
              ),
            ),
          ],
        ),
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
        hasMusic: music != null,
        error: error,
        onSet: onSet,
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
    return Padding(
      // The keyboard inset, or the field sits under it on a short screen.
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('what should play?', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            'paste a Spotify link. it opens in your Spotify app, so you need '
            'Spotify installed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              hintText: 'https://open.spotify.com/playlist/...',
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
