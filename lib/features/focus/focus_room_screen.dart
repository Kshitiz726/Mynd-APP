import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/focus/room_participant.dart';
import '../community/moderation_sheet.dart';
import '../../providers/focus_room_provider.dart';
import 'widgets/focus_music.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import '../community/widgets/room_code.dart';
import 'focus_help.dart';

class FocusRoomScreen extends StatefulWidget {
  const FocusRoomScreen({super.key});

  @override
  State<FocusRoomScreen> createState() => _FocusRoomScreenState();
}

class _FocusRoomScreenState extends State<FocusRoomScreen> {
  @override
  Widget build(BuildContext context) {
    final fr = context.watch<FocusRoomProvider>();
    final c = context.omColors;
    final me =
        fr.participants.where((p) => p.userId == fr.myUserId).firstOrNull;

    // Find active task and timer from me, or from the host, or just anyone running
    final activeParticipant = me?.timerRunning == true
        ? me
        : (fr.participants.where((p) => p.timerRunning).firstOrNull ?? me);

    final isNeedHelp = me?.state == ParticipantState.needHelp;

    // Timer text - the true elapsed time, fully independent of the ring.
    final secs = fr.myElapsedSecs;
    final m = secs ~/ 60;
    final s = secs % 60;
    final timeString =
        '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    const ringTau = 1200.0; // seconds
    final progress = 1 - math.exp(-secs / ringTau);

    return Scaffold(
      backgroundColor: c.bg,
      // Nothing on this screen takes typing, so a keyboard here always belongs
      // to somewhere else: it rides in from the join-code field or the invite
      // sheet and lingers for a frame. Reflowing the room around it shrank the
      // body by roughly a keyboard, the Spacers went to zero, and the fixed
      // content underneath ran 105px past the bottom. The room simply does not
      // move for a keyboard now.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Vibrant ambience wash - always present (and the only backdrop on
          // desktop where video isn't supported). Crossfades when the ambience
          // is switched so cafe → rain → … actually changes the room's mood.
          AnimatedContainer(
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _ambienceGradient(fr.ambience),
              ),
            ),
          ),
          // Glassy Overlay for Readability
          Container(
            color: context.isDark
                ? Colors.black.withValues(alpha: 0.7)
                : Colors.white.withValues(alpha: 0.8),
          ),

          SafeArea(
            child: LayoutBuilder(builder: (context, box) {
              // A short viewport (a small phone, or landscape) cannot hold the
              // room at its natural size: the flexible gaps collapse to zero
              // and the fixed content below them runs off the bottom. Under
              // this height the room scrolls instead of squeezing, which is
              // the only layout that cannot overflow.
              final tight = box.maxHeight < 660;
              Widget gap() => tight
                  ? const SizedBox(height: AppSpacing.lg)
                  : const Spacer();
              final column = Column(
                children: [
                  AppBar(
                    backgroundColor: Colors.transparent,
                    elevation: 0,
                    automaticallyImplyLeading: false,
                    // Backing out is not leaving. You stay in the room, still
                    // counted in it, and can go do something else in the app and
                    // come back - only "Leave Room" takes you out.
                    leading: OmBackButton(
                      onTap: () {
                        Haptics.light();
                        fr.minimiseRoom();
                        Toast.show(context,
                            "Still in the room - tap the pill to come back.");
                      },
                    ),
                    title: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(fr.activeRoom?.title ?? 'Focus Room',
                            style: Theme.of(context).textTheme.titleMedium),
                        // The code lives where you are when someone asks for it.
                        if (fr.activeRoom != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: RoomCodeChip(room: fr.activeRoom!),
                          ),
                      ],
                    ),
                    toolbarHeight: 78,
                    centerTitle: true,
                    actions: [
                      OmTappable(
                        onTap: () {
                          Haptics.light();
                          _showMembers(context, fr);
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(OmIcons.byName('users'),
                                  color: c.text, size: 20),
                              const SizedBox(width: 5),
                              Text('${fr.participantCount}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelLarge
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),

                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'CURRENT FOCUS',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: c.primary,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    activeParticipant?.task?.isNotEmpty == true
                        ? activeParticipant!.task!
                        : 'Focusing together',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  gap(),
                  _TimerCircle(
                      progress: progress,
                      time: timeString,
                      running: activeParticipant?.timerRunning ?? false),
                  gap(),

                  // Participant Grid
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    child: Wrap(
                      spacing: 20,
                      runSpacing: 20,
                      alignment: WrapAlignment.center,
                      children: [
                        for (final p in fr.participants)
                          _ParticipantTile(
                            userId: p.userId,
                            name:
                                p.userId == fr.myUserId ? 'You' : p.displayName,
                            initial: p.initial,
                            color: _hex(p.avatarColor),
                            needsHelp: p.state == ParticipantState.needHelp,
                            dimmed: p.state == ParticipantState.inactive,
                            isMe: p.userId == fr.myUserId,
                          ),
                      ],
                    ),
                  ),

                  gap(),
                  // Controls
                  Padding(
                    padding: EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                        vertical: tight ? AppSpacing.md : AppSpacing.xl),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _ControlButton(
                          label: 'Need Help',
                          icon: 'life-buoy',
                          active: isNeedHelp,
                          activeColor: c.primary,
                          onTap: () async {
                            Haptics.medium();
                            // Leave the room and go straight to Mynd, primed with a
                            // "help me focus" prompt.
                            await fr.leaveRoom();
                            if (context.mounted) {
                              Navigator.of(context).maybePop();
                              askMyndForHelp(context);
                            }
                          },
                        ),
                        _ControlButton(
                          label: fr.ambience,
                          icon: _ambienceIcon(fr.ambience),
                          active: false,
                          activeColor: c.text2,
                          onTap: () {
                            Haptics.light();
                            // cycle ambience
                            const cycle = [
                              'cafe',
                              'silent',
                              'rain',
                              'library',
                              'typing'
                            ];
                            final next = cycle[
                                (cycle.indexOf(fr.ambience) + 1) %
                                    cycle.length];
                            fr.setAmbience(next);
                          },
                        ),
                      ],
                    ),
                  ),
                  // One line under the controls: what the room is playing and
                  // a pause that reaches everyone. There is no player to see -
                  // the audio comes out of Mynd and the screen stays about the
                  // session, which is what people came for.
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
                    child: RoomMusicStrip(),
                  ),
                  // Leave Button
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.screenH, vertical: 8),
                    child: SizedBox(
                      width: double.infinity,
                      child: OmTappable(
                        onTap: () async {
                          Haptics.medium();
                          await fr.leaveRoom();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          alignment: Alignment.center,
                          child: Text('Leave Room',
                              style: TextStyle(
                                  color: c.error, fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ),
                  ),
                ],
              );
              return tight ? SingleChildScrollView(child: column) : column;
            }),
          ),
        ],
      ),
    );
  }

  Color _hex(String? s) {
    if (s == null) return const Color(0xFF6366F1);
    var h = s.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? const Color(0xFF6366F1) : Color(v);
  }

  String _ambienceIcon(String a) {
    switch (a) {
      case 'cafe':
        return 'coffee';
      case 'silent':
        return 'moon';
      case 'rain':
        return 'cloud-rain';
      case 'library':
        return 'book';
      case 'typing':
        return 'keyboard';
      default:
        return 'wind';
    }
  }

  /// A distinct, vibrant 2-colour wash per ambience so switching the option
  /// visibly recolours the whole room (works on every platform, video or not).
  List<Color> _ambienceGradient(String a) {
    switch (a) {
      case 'cafe': // warm amber / latte
        return const [Color(0xFFFFB75E), Color(0xFFED8F03)];
      case 'rain': // cool storm blue
        return const [Color(0xFF4B6CB7), Color(0xFF182848)];
      case 'silent': // deep calm indigo
        return const [Color(0xFF654EA3), Color(0xFF2C1A4D)];
      case 'library': // soft sage green
        return const [Color(0xFF56AB91), Color(0xFF20614B)];
      case 'typing': // fresh teal
        return const [Color(0xFF36D1DC), Color(0xFF1B7B86)];
      default:
        return const [Color(0xFFFFB75E), Color(0xFFED8F03)];
    }
  }

  /// Bottom sheet listing everyone currently in the room (avatars + names),
  /// opened from the people-count chip in the top-right of the room.
  void _showMembers(BuildContext context, FocusRoomProvider fr) {
    final c = context.omColors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.bg,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) {
        final people = fr.participants;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('in this room · ${people.length}',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              for (final p in people)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(
                    children: [
                      OmAvatar(
                        userId: p.userId,
                        fallbackInitial: p.initial,
                        fallbackColor: _hex(p.avatarColor),
                        size: 42,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          p.userId == fr.myUserId ? 'You' : p.displayName,
                          style: Theme.of(context).textTheme.bodyLarge,
                        ),
                      ),
                      if (p.state == ParticipantState.needHelp)
                        Icon(OmIcons.byName('life-buoy'),
                            size: 18, color: c.primary)
                      else if (p.timerRunning)
                        Icon(OmIcons.byName('timer'),
                            size: 18, color: c.success),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TimerCircle extends StatelessWidget {
  const _TimerCircle(
      {required this.progress, required this.time, required this.running});

  final double progress;
  final String time;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 220,
          height: 220,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: progress),
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => CircularProgressIndicator(
              value: value,
              strokeWidth: 12,
              strokeCap: StrokeCap.round,
              backgroundColor: c.primaryTint,
              valueColor: AlwaysStoppedAnimation<Color>(c.primary),
            ),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              time,
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1),
            ),
            Text('elapsed',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: c.text2,
                      fontSize: 13,
                      letterSpacing: 0.5,
                    )),
          ],
        ),
      ],
    );
  }
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.userId,
    required this.name,
    required this.initial,
    required this.color,
    required this.needsHelp,
    required this.dimmed,
    this.isMe = false,
  });

  final String userId;
  final String name;
  final String initial;
  final Color color;
  final bool needsHelp;
  final bool dimmed;

  /// Reporting yourself is never the intent, so the gesture is off on your own
  /// tile rather than opening a sheet that makes no sense.
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // Long-press to report or block. This is the surface Apple cares most about
    // on this app: a focus room carries live voice, so the person beside you can
    // talk into your ear. The community feed is parked out of the shell, which
    // makes these tiles - not the post cards - the place moderation has to
    // actually be reachable.
    //
    // Long-press rather than a visible control, because the tile is 56px of
    // avatar in a wrap of other people and a permanent (...) on each one would
    // bury the room in chrome. The room's own help sheet names the gesture, and
    // so do the App Review notes.
    return GestureDetector(
      onLongPress: isMe
          ? null
          : () async {
              Haptics.medium();
              await showModerationSheet(
                context,
                targetType: 'user',
                targetId: userId,
                authorId: userId,
                authorName: name,
              );
            },
      child: Opacity(
      opacity: dimmed ? 0.4 : 1.0,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: needsHelp ? Border.all(color: c.primary, width: 3) : null,
            ),
            child: OmAvatar(
              userId: userId,
              fallbackInitial: initial,
              fallbackColor: color,
              size: 56,
            ),
          ),
          const SizedBox(height: 6),
          Text(name,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontSize: 13)),
        ],
      ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final String icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final color = active ? activeColor : c.text;
    final bgColor = active ? activeColor.withValues(alpha: 0.1) : c.surface;

    return OmTappable(
      onTap: onTap,
      pressedScale: 0.9,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              boxShadow: active
                  ? []
                  : [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
            ),
            alignment: Alignment.center,
            child: Icon(OmIcons.byName(icon), size: 22, color: color),
          ),
          const SizedBox(height: 8),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
