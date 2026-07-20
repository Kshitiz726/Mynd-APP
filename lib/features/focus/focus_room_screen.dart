import 'dart:math' as math;

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/focus/room_participant.dart';
import '../../providers/focus_room_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import 'focus_help.dart';

class FocusRoomScreen extends StatefulWidget {
  const FocusRoomScreen({super.key});

  @override
  State<FocusRoomScreen> createState() => _FocusRoomScreenState();
}

class _FocusRoomScreenState extends State<FocusRoomScreen> {
  late VideoPlayerController _videoController;
  String _currentAmbience = '';
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    // Start with a generic placeholder URL (it will immediately update if Provider has a different value)
    _initVideo('cafe');
  }

  bool get _isVideoSupported => kIsWeb || Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  void _initVideo(String ambience) {
    _currentAmbience = ambience;
    
    if (!_isVideoSupported) {
      // Safely fallback for Windows/Linux
      return;
    }
    
    final url = _getVideoUrl(ambience);
    
    _videoController = VideoPlayerController.networkUrl(Uri.parse(url))
      ..initialize().then((_) {
        _videoController.setLooping(true);
        _videoController.setVolume(0.0);
        _videoController.play();
        if (mounted) {
          setState(() {
            _isVideoInitialized = true;
          });
        }
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final fr = context.watch<FocusRoomProvider>();
    if (fr.ambience != _currentAmbience) {
      if (!_isVideoSupported) {
        _currentAmbience = fr.ambience;
        return;
      }
      
      final oldController = _videoController;
      final newUrl = _getVideoUrl(fr.ambience);
      
      final newController = VideoPlayerController.networkUrl(Uri.parse(newUrl));
      newController.initialize().then((_) {
        newController.setLooping(true);
        newController.setVolume(0.0);
        newController.play();
        
        if (mounted) {
          setState(() {
            _videoController = newController;
            _currentAmbience = fr.ambience;
          });
        }
        
        // Smooth crossfade, dispose old controller after a delay
        Future.delayed(const Duration(milliseconds: 1000), () {
          oldController.dispose();
        });
      });
    }
  }

  String _getVideoUrl(String ambience) {
    // Map ambiences to reliable sample video loops to achieve the requested effect.
    switch (ambience) {
      case 'rain':
        return 'https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4';
      case 'cafe':
        return 'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4';
      case 'silent':
        return 'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4';
      case 'library':
        return 'https://storage.googleapis.com/gtv-videos-bucket/sample/TearsOfSteel.mp4';
      case 'typing':
        return 'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerJoyrides.mp4';
      default:
        return 'https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4';
    }
  }

  @override
  void dispose() {
    if (_isVideoSupported && _isVideoInitialized) {
      _videoController.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fr = context.watch<FocusRoomProvider>();
    final c = context.omColors;
    final me = fr.participants.where((p) => p.userId == fr.myUserId).firstOrNull;
    
    // Find active task and timer from me, or from the host, or just anyone running
    final activeParticipant = me?.timerRunning == true ? me : (fr.participants.where((p) => p.timerRunning).firstOrNull ?? me);
    
    final isNeedHelp = me?.state == ParticipantState.needHelp;

    // Timer text - the true elapsed time, fully independent of the ring.
    final secs = fr.myElapsedSecs;
    final m = secs ~/ 60;
    final s = secs % 60;
    final timeString = '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';

    const ringTau = 1200.0; // seconds
    final progress = 1 - math.exp(-secs / ringTau);

    return Scaffold(
      backgroundColor: c.bg,
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
          // Background Video Ambience
          if (_isVideoInitialized)
            AnimatedSwitcher(
              duration: const Duration(seconds: 1),
              child: SizedBox.expand(
                key: ValueKey(_videoController.dataSource),
                child: FittedBox(
                  fit: BoxFit.cover,
                  child: SizedBox(
                    width: _videoController.value.size.width,
                    height: _videoController.value.size.height,
                    child: VideoPlayer(_videoController),
                  ),
                ),
              ),
            ),
            
          // Glassy Overlay for Readability
          Container(
            color: context.isDark ? Colors.black.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.8),
          ),
          
          SafeArea(
            child: Column(
              children: [
                AppBar(
                  backgroundColor: Colors.transparent,
                  elevation: 0,
                  automaticallyImplyLeading: false,
                  leading: OmBackButton(
                    onTap: () async {
                      Haptics.medium();
                      await fr.leaveRoom();
                      if (context.mounted) Navigator.of(context).maybePop();
                    },
                  ),
                  title: Text(fr.activeRoom?.title ?? 'Focus Room', style: Theme.of(context).textTheme.titleMedium),
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
                            Icon(OmIcons.byName('users'), color: c.text, size: 20),
                            const SizedBox(width: 5),
                            Text('${fr.participantCount}',
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.primary, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                ),
                const SizedBox(height: 8),
                Text(
                  activeParticipant?.task?.isNotEmpty == true ? activeParticipant!.task! : 'Focusing together',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                _TimerCircle(progress: progress, time: timeString, running: activeParticipant?.timerRunning ?? false),
                const Spacer(),
                
                // Participant Grid
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final p in fr.participants)
                        _ParticipantTile(
                          userId: p.userId,
                          name: p.userId == fr.myUserId ? 'You' : p.displayName,
                          initial: p.initial,
                          color: _hex(p.avatarColor),
                          needsHelp: p.state == ParticipantState.needHelp,
                          dimmed: p.state == ParticipantState.inactive,
                        ),
                    ],
                  ),
                ),
                
                const Spacer(),
                // Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: AppSpacing.xl),
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
                          const cycle = ['cafe', 'silent', 'rain', 'library', 'typing'];
                          final next = cycle[(cycle.indexOf(fr.ambience) + 1) % cycle.length];
                          fr.setAmbience(next);
                        },
                      ),
                    ],
                  ),
                ),
                // Leave Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH, vertical: 8),
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
                        child: Text('Leave Room', style: TextStyle(color: c.error, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
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
    switch(a) {
      case 'cafe': return 'coffee';
      case 'silent': return 'moon';
      case 'rain': return 'cloud-rain';
      case 'library': return 'book';
      case 'typing': return 'keyboard';
      default: return 'wind';
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
                        Icon(OmIcons.byName('life-buoy'), size: 18, color: c.primary)
                      else if (p.timerRunning)
                        Icon(OmIcons.byName('timer'), size: 18, color: c.success),
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
  const _TimerCircle({required this.progress, required this.time, required this.running});

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
              style: Theme.of(context)
                  .textTheme
                  .headlineLarge
                  ?.copyWith(fontSize: 44, fontWeight: FontWeight.w800, letterSpacing: -1),
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
  });

  final String userId;
  final String name;
  final String initial;
  final Color color;
  final bool needsHelp;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Opacity(
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
          Text(name, style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 13)),
        ],
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
                  : [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))],
            ),
            alignment: Alignment.center,
            child: Icon(OmIcons.byName(icon), size: 22, color: color),
          ),
          const SizedBox(height: 8),
          Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
