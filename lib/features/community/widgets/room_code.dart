import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/api_client.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../core/utils/toast.dart';
import '../../../models/focus/focus_room.dart';
import '../../../providers/focus_room_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';

/// "Join with a code" - the way into a private room, and the way a friend gets
/// into yours without hunting through a list.
///
/// Four characters, no ambiguous glyphs, uppercased as you type. A code is a
/// thing you say out loud or text to someone, so everything here is built for
/// it arriving slightly mangled: spaces, lowercase and stray hyphens are all
/// stripped before it goes to the server.
class JoinByCodeCard extends StatefulWidget {
  const JoinByCodeCard({super.key});

  @override
  State<JoinByCodeCard> createState() => _JoinByCodeCardState();
}

class _JoinByCodeCardState extends State<JoinByCodeCard> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _ctrl.text.trim();
    if (code.length < 4 || _busy) return;
    setState(() => _busy = true);
    final rooms = context.read<FocusRoomProvider>();
    try {
      final room = await ApiClient.instance.joinRoomByCode(code);
      if (!mounted) return;
      Haptics.success();
      // A private room is not in the lobby list, so add it before joining or
      // the room screen has nothing to render.
      rooms.addRoom(room);
      rooms.joinRoom(room.id);
      _ctrl.clear();
      FocusManager.instance.primaryFocus?.unfocus();
    } catch (_) {
      if (!mounted) return;
      Haptics.error();
      Toast.show(context, "No room with that code. Check it and try again.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: OmGlass(
        borderRadius: 22,
        blur: 24,
        opacity: context.isDark ? 0.32 : 0.55,
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        child: Row(
          children: [
            Icon(OmIcons.byName('lock'), size: 16, color: c.text2),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _ctrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 6,
                onSubmitted: (_) => _join(),
                onChanged: (_) => setState(() {}),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]')),
                  TextInputFormatter.withFunction(
                    (_, next) => next.copyWith(text: next.text.toUpperCase()),
                  ),
                ],
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      letterSpacing: 5,
                      fontWeight: FontWeight.w800,
                    ),
                decoration: InputDecoration(
                  counterText: '',
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintText: 'join with a code',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: c.text2,
                        letterSpacing: 0,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ),
            OmTappable(
              onTap: _ctrl.text.trim().length >= 4 ? _join : null,
              feedback: OmTapFeedback.none,
              pressedScale: 0.9,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 180),
                opacity: _ctrl.text.trim().length >= 4 ? 1 : 0.35,
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration:
                  BoxDecoration(color: c.brandSolid, shape: BoxShape.circle),
                  child: _busy
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The code for a room you are in, with the two things you actually want to do
/// with it: copy it, or hand it to someone.
class RoomCodeChip extends StatelessWidget {
  const RoomCodeChip({super.key, required this.room});

  final FocusRoom room;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final code = room.code;
    if (code == null || code.isEmpty) return const SizedBox.shrink();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OmTappable(
          onTap: () {
            Haptics.light();
            Clipboard.setData(ClipboardData(text: code));
            Toast.show(context, 'Code copied');
          },
          feedback: OmTapFeedback.none,
          pressedScale: 0.94,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: c.surfaceAlt,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  code,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        letterSpacing: 3,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 8),
                Icon(OmIcons.byName('file'), size: 13, color: c.text2),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        OmTappable(
          onTap: () {
            Haptics.medium();
            // The invite is the code plus one sentence of context, on the
            // clipboard ready to paste wherever they already talk to this
            // person. A one-tap deep link would be better and needs app-link
            // configuration on both platforms; this works today, on both.
            Clipboard.setData(ClipboardData(
              text: 'Come focus with me on OurMynd. '
                  'Open Focus rooms and join with code $code.',
            ));
            Toast.show(context, 'Invite copied - paste it to your friend');
          },
          feedback: OmTapFeedback.none,
          pressedScale: 0.94,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              gradient: c.brandGradient,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: const Text(
              'invite a friend',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}
