import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/api_client.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../widgets/om_back_button.dart';
import '../../core/utils/toast.dart';
import '../../models/focus/body_double.dart';
import '../../models/focus_mode.dart';
import '../../providers/focus_provider.dart';
import '../../providers/focus_room_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_button.dart';
import '../../widgets/om_tappable.dart';

/// Body doubling matchmaking. Two ways in:
///   • Auto-match - queue up; pair with the next solo user (socket `bd_matched`).
///   • Invite a friend - create the room now and notify a specific friend.
/// On pairing we show the partner's generated avatar + name, then drop both into
/// a shared focus room.
class BodyDoublingScreen extends StatefulWidget {
  const BodyDoublingScreen({super.key, this.autoStart = false, this.mode});

  /// When true, jump straight into auto-match on open (skip the idle screen).
  final bool autoStart;
  final FocusMode? mode;

  @override
  State<BodyDoublingScreen> createState() => _BodyDoublingScreenState();
}

enum _Mode { auto, invite }

enum _Phase { idle, searching, matched }

class _BodyDoublingScreenState extends State<BodyDoublingScreen> {
  final _rt = RealtimeService.instance;

  _Mode _mode = _Mode.auto;
  _Phase _phase = _Phase.idle;

  BdPartner? _partner;
  String? _roomId;

  List<BdFriend>? _friends;
  bool _loadingFriends = false;
  String? _invitedName;

  @override
  void initState() {
    super.initState();
    // Partner found while we were waiting in the queue.
    _rt.on('bd_matched', (d) {
      if (!mounted) return;
      setState(() {
        _partner = BdPartner.fromJson((d['partner'] as Map).cast());
        _roomId = d['roomId'] as String?;
        _phase = _Phase.matched;
      });
      Haptics.success();
    });
    // Kick off matchmaking immediately when launched from "start" with body
    // doubling on - no extra tap needed.
    if (widget.autoStart) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startMatch();
      });
    }
  }

  @override
  void dispose() {
    _rt.off('bd_matched');
    // Best-effort leave the queue if we back out mid-search.
    if (_phase == _Phase.searching) {
      ApiClient.instance.bodyDoublingCancel().catchError((_) {});
    }
    super.dispose();
  }

  Color _hex(String? s, Color fallback) {
    if (s == null) return fallback;
    var h = s.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  Future<void> _startMatch() async {
    setState(() => _phase = _Phase.searching);
    Haptics.medium();
    try {
      final m = await ApiClient.instance.bodyDoublingMatch();
      if (!mounted) return;
      if (m.matched) {
        setState(() {
          _partner = m.partner;
          _roomId = m.roomId;
          _phase = _Phase.matched;
        });
        Haptics.success();
      }
      // else: stay in searching; bd_matched will arrive over the socket.
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.idle);
      Toast.show(context, "Couldn't start matchmaking");
    }
  }

  Future<void> _cancelMatch() async {
    setState(() => _phase = _Phase.idle);
    try {
      await ApiClient.instance.bodyDoublingCancel();
    } catch (_) {}
  }

  void _enterRoom() {
    final id = _roomId;
    if (id == null) return;
    Haptics.medium();
    
    if (widget.mode != null) {
      context.read<FocusProvider>().start(
        widget.mode!, 
        true, 
        preMatchedRoomId: id,
        preMatchedPartnerName: _partner?.name ?? _invitedName,
      );
      Navigator.of(context).maybePop();
    } else {
      context.read<FocusRoomProvider>().joinRoom(id);
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _loadFriends() async {
    if (_friends != null || _loadingFriends) return;
    setState(() => _loadingFriends = true);
    try {
      final all = await ApiClient.instance.fetchFriends();
      if (mounted) setState(() => _friends = all.where((f) => f.accepted).toList());
    } catch (_) {
      if (mounted) setState(() => _friends = []);
    } finally {
      if (mounted) setState(() => _loadingFriends = false);
    }
  }

  Future<void> _invite(BdFriend f) async {
    Haptics.medium();
    try {
      final roomId = await ApiClient.instance.bodyDoublingInvite(f.id);
      if (!mounted) return;
      setState(() {
        _roomId = roomId;
        _invitedName = f.name;
      });
      Toast.show(context, 'Invited ${f.name} - they\'ll get a notification');
    } catch (_) {
      if (mounted) Toast.show(context, "Couldn't send invite");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Focus together'),
        automaticallyImplyLeading: false,
        leading: const OmBackButton(),
        leadingWidth: 58,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.lg),
              // "Invite a friend" is parked for now - only stranger auto-match is
              // offered, so there's no mode toggle.
              Expanded(
                child: _phase == _Phase.matched ? _matchedView(c) : _autoView(c),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Auto-match ──
  Widget _autoView(OmColors c) {
    if (_phase == _Phase.searching) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _PulsingFinder(color: c.primary),
          const SizedBox(height: AppSpacing.xl),
          Text('Looking for a focus partner…',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('You’ll be paired the moment someone else is ready.',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          OmButton(label: 'Cancel', variant: OmButtonVariant.soft, onPressed: _cancelMatch),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 110,
          height: 110,
          decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
          child: Icon(OmIcons.byName('users'), size: 48, color: c.primary),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Get matched with a stranger',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('We’ll pair you with someone else who wants to body-double right now.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xl),
        OmButton(label: 'Find a partner', icon: OmIcons.byName('zap'), onPressed: _startMatch),
      ],
    );
  }

  // ── Invite a friend ──
  Widget _inviteView(OmColors c) {
    if (_invitedName != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(OmIcons.byName('check'), size: 56, color: c.success),
          const SizedBox(height: AppSpacing.lg),
          Text('Invited $_invitedName',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('They’ll get a notification to join. You can head in now.',
              textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: AppSpacing.xl),
          OmButton(label: 'Enter the room', icon: OmIcons.byName('activity'), onPressed: _enterRoom),
        ],
      );
    }
    if (_loadingFriends) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final friends = _friends ?? [];
    if (friends.isEmpty) {
      return Center(
        child: Text('No friends yet - follow people in Community first.',
            textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
      );
    }
    return ListView.separated(
      itemCount: friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, i) {
        final f = friends[i];
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              OmAvatar(userId: f.id, fallbackInitial: f.initial, fallbackColor: _hex(f.color, c.primary), size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(f.name,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
              OmTappable(
                onTap: () => _invite(f),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  decoration: BoxDecoration(gradient: c.brandGradient, borderRadius: BorderRadius.circular(12)),
                  child: const Text('Invite',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Matched ──
  Widget _matchedView(OmColors c) {
    final p = _partner;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('YOU’RE PAIRED',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: c.primary, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
        const SizedBox(height: AppSpacing.xl),
        if (p != null)
          OmAvatar(userId: p.id, fallbackInitial: p.initial, fallbackColor: _hex(p.color, c.primary), size: 96),
        const SizedBox(height: AppSpacing.md),
        Text(p?.name ?? 'Your partner',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Text('is ready to focus alongside you.',
            style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: AppSpacing.xxl),
        OmButton(label: 'Start focusing together', icon: OmIcons.byName('activity'), onPressed: _enterRoom),
      ],
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});

  final _Mode mode;
  final ValueChanged<_Mode>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    Widget seg(String label, _Mode m) {
      final active = mode == m;
      return Expanded(
        child: OmTappable(
          onTap: onChanged == null ? null : () => onChanged!(m),
          feedback: OmTapFeedback.select,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 11),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? c.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              boxShadow: active
                  ? [BoxShadow(color: c.shadow.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))]
                  : null,
            ),
            child: Text(label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: active ? c.text : c.text2,
                    )),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [seg('Auto match', _Mode.auto), seg('Invite friend', _Mode.invite)]),
    );
  }
}

/// Concentric pulsing rings around a search glyph - the "looking…" affordance.
class _PulsingFinder extends StatefulWidget {
  const _PulsingFinder({required this.color});
  final Color color;

  @override
  State<_PulsingFinder> createState() => _PulsingFinderState();
}

class _PulsingFinderState extends State<_PulsingFinder> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return Stack(
            alignment: Alignment.center,
            children: [
              ...List.generate(3, (i) {
                final t = (_ctrl.value + i / 3) % 1.0;
                return Container(
                  width: 70 + t * 90,
                  height: 70 + t * 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: widget.color.withValues(alpha: (1 - t) * 0.4)),
                  ),
                );
              }),
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                child: Icon(OmIcons.byName('users'), color: Colors.white, size: 30),
              ),
            ],
          );
        },
      ),
    );
  }
}
