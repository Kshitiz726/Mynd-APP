import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/api_client.dart';
import '../../core/services/api_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/community/post.dart';
import '../../models/community/chat_models.dart';
import '../../models/energy_level.dart';
import '../../models/focus/focus_room.dart';
import '../../providers/alerts_provider.dart';
import '../../providers/community_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/focus_room_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_card.dart';
import '../../widgets/om_glass.dart';
import '../../widgets/om_tappable.dart';
import '../home/search/global_search_screen.dart';
import '../notifications/notifications_screen.dart';
import 'chat_screen.dart';
import 'new_dm_sheet.dart';
import 'widgets/post_comments_sheet.dart';
import 'package:audioplayers/audioplayers.dart';

final _audio = AudioPlayer();

/// Maps an [EnergyLevel] mood to the pill label used on post cards.
String _moodLabel(EnergyLevel? m) => switch (m) {
      EnergyLevel.high => 'Energized',
      EnergyLevel.low => 'Low Energy',
      EnergyLevel.dead => 'Brain-dead',
      null => '',
    };

/// Parses a '#RRGGBB' hex string into a [Color] (feed avatars come as hex).
Color _hex(String s, [Color fallback = const Color(0xFF6366F1)]) {
  var h = s.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

// Groups and DMs are parked while the core loop is built out; the tabs, their
// bodies and the provider wiring all still exist below, commented, so bringing
// them back is a one-line change rather than a rewrite.
enum _CmTab { feed, rooms /*, groups, chats */ }

/// "community" - a calm feed, focus rooms, interest groups and DMs. Mirrors
/// the prototype's `#screen-community` (hero card → tabs → per-tab content).
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  _CmTab _tab = _CmTab.feed;

  @override
  void initState() {
    super.initState();
    // Load the feed + live rooms from the backend after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      context.read<CommunityProvider>().loadFeed(refresh: true);
      try {
        final r = await ApiClient.instance.fetchRooms();
        if (mounted) context.read<FocusRoomProvider>().setRooms(r.rooms, r.globalLive);
      } catch (_) {/* server offline - UI shows empty state */}
    });
  }

  /// Pull-to-refresh: re-pull the feed (latest posts) and the live rooms so the
  /// user can pull down to see new activity on demand.
  Future<void> _refresh() async {
    await context.read<CommunityProvider>().loadFeed(refresh: true);
    try {
      final r = await ApiClient.instance.fetchRooms();
      if (mounted) context.read<FocusRoomProvider>().setRooms(r.rooms, r.globalLive);
    } catch (_) {/* server offline */}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;

    return Stack(
      children: [
        // The glass cards need something to refract: peach at the top cooling
        // into brand lilac, so every card sits on colour rather than on grey.
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color.lerp(const Color(0xFFFFD9BE), c.surface, context.isDark ? 0.84 : 0.42)!,
                  Color.lerp(const Color(0xFFFFC9D6), c.surface, context.isDark ? 0.86 : 0.58)!,
                  Color.lerp(c.primary, c.surface, context.isDark ? 0.88 : 0.72)!,
                  c.surface,
                ],
                stops: const [0.0, 0.26, 0.62, 1.0],
              ),
            ),
          ),
        ),
        RefreshIndicator(
          onRefresh: _refresh,
          color: c.primary,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(0, AppSpacing.screenTop, 0, AppSpacing.screenBottom),
            children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: _FeedHeader(),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Padding(padding: EdgeInsets.symmetric(horizontal: AppSpacing.screenH), child: _HeroCard()),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
              child: _CmTabs(current: _tab, onChanged: (t) => setState(() => _tab = t)),
            ),
            const SizedBox(height: AppSpacing.md),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) {
                final slide = Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero)
                    .animate(anim);
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(position: slide, child: child),
                );
              },
              layoutBuilder: (current, previous) => Stack(
                alignment: Alignment.topCenter,
                children: [...previous, if (current != null) current],
              ),
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: switch (_tab) {
                  _CmTab.feed => const _FeedTab(),
                  _CmTab.rooms => const _RoomsTab(),
                  // _CmTab.groups => const _GroupsTab(),
                  // _CmTab.chats => const _ChatsTab(),
                },
              ),
            ),
            ],
          ),
        ),
        // The reference's one primary action: a floating "+" that writes a post.
        // It replaces the old inline composer, so the feed is nothing but feed.
        if (_tab == _CmTab.feed)
          Positioned(
            right: AppSpacing.screenH + 2,
            bottom: 96,
            child: _NewPostFab(onTap: () => _ComposerSheet.open(context)),
          ),
      ],
    );
  }
}

/// The reference's header: your face, a search pill, alerts, people. Icon-only
/// and evenly weighted, so nothing here competes with the feed itself.
class _FeedHeader extends StatelessWidget {
  const _FeedHeader();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final name = ApiConfig.instance.displayName ?? 'You';
    final userId = ApiConfig.instance.userId ?? name;
    final unread = context.watch<AlertsProvider>().alertsUnread;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.surface,
            boxShadow: [
              BoxShadow(
                color: c.shadow.withValues(alpha: context.isDark ? 0.45 : 0.12),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: OmAvatar(
            userId: userId,
            fallbackInitial: name.isNotEmpty ? name[0].toUpperCase() : 'Y',
            fallbackColor: c.primary,
            size: 40,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OmTappable(
            onTap: () {
              Haptics.select();
              GlobalSearchScreen.open(context);
            },
            feedback: OmTapFeedback.none,
            pressedScale: 0.98,
            child: OmGlass(
              borderRadius: AppRadius.pill,
              blur: 24,
              opacity: context.isDark ? 0.34 : 0.72,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(OmIcons.byName('search'), size: 17, color: c.text2),
                  const SizedBox(width: 8),
                  Text(
                    'search',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2, fontSize: 14.5),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _HeaderIcon(
          icon: 'bell',
          dot: unread > 0,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
          ),
        ),
        const SizedBox(width: 6),
        _HeaderIcon(icon: 'users', onTap: () => NewDmSheet.show(context)),
      ],
    );
  }
}

/// A glass disc in the header. The red dot is the same alerts count the nav bar
/// shows, so the two never disagree.
class _HeaderIcon extends StatelessWidget {
  const _HeaderIcon({required this.icon, required this.onTap, this.dot = false});

  final String icon;
  final VoidCallback onTap;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: () {
        Haptics.select();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.9,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          OmGlass(
            borderRadius: AppRadius.pill,
            blur: 24,
            opacity: context.isDark ? 0.34 : 0.72,
            padding: const EdgeInsets.all(11),
            child: Icon(OmIcons.byName(icon), size: 18, color: c.text),
          ),
          if (dot)
            Positioned(
              right: 9,
              top: 9,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: c.error,
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The floating compose button.
class _NewPostFab extends StatelessWidget {
  const _NewPostFab({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: () {
        Haptics.medium();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.9,
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          // Accent, not brand: the nav bar's centre "+" is already brand
          // purple, and two identical discs on one screen is a coin toss.
          // The reference's floating button is coral anyway.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c.accent, Color.lerp(c.accent, Colors.black, 0.14)!],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: c.accent.withValues(alpha: 0.45),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.add_rounded, size: 30, color: Colors.white),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();

  static const _avatars = [('M', Color(0xFF6366F1)), ('A', Color(0xFF10B981)), ('L', Color(0xFFEC4899)), ('J', Color(0xFFF59E0B))];

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final live = context.watch<FocusRoomProvider>().globalLive;
    return GestureDetector(
      onTap: () => Toast.show(context, 'Opens focus room pre-join'),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: context.isDark ? 0.4 : 0.08),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: OmGlass(
          borderRadius: 24,
          blur: 26,
          opacity: context.isDark ? 0.38 : 0.8,
          padding: const EdgeInsets.all(16),
          child: Row(
          children: [
            SizedBox(
              width: 88,
              height: 28,
              child: Stack(
                children: [
                  for (var i = 0; i < _avatars.length; i++)
                    Positioned(
                      left: i * 20.0,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _avatars[i].$2,
                          border: Border.all(color: c.surface, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: Text(_avatars[i].$1,
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.text),
                  children: [
                    TextSpan(text: '$live ', style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
                    const TextSpan(text: 'minds focusing right now'),
                  ],
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: 6, height: 6, decoration: BoxDecoration(color: c.success, shape: BoxShape.circle)),
                const SizedBox(width: 4),
                Text('LIVE', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.success, letterSpacing: 0.5)),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }
}

class _CmTabs extends StatelessWidget {
  const _CmTabs({required this.current, required this.onChanged});

  final _CmTab current;
  final ValueChanged<_CmTab> onChanged;

  static const _labels = {
    _CmTab.feed: 'Latest Activities',
    _CmTab.rooms: 'Focus rooms',
    // _CmTab.groups: 'Groups', _CmTab.chats: 'Chats',
  };

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // Underlined text rather than a boxed segment: the reference leads with the
    // words and marks the active one with a short brand rule beneath it, with a
    // count badge riding alongside the label it belongs to.
    final counts = {
      _CmTab.feed: context.watch<CommunityProvider>().posts.length,
      _CmTab.rooms: context.watch<FocusRoomProvider>().rooms.length,
    };

    return Row(
      children: [
        for (final t in _CmTab.values)
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: OmTappable(
              onTap: () {
                Haptics.select();
                onChanged(t);
              },
              feedback: OmTapFeedback.none,
              pressedScale: 0.96,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: Theme.of(context).textTheme.titleMedium!.copyWith(
                              color: t == current ? c.text : c.text2,
                              fontSize: 15.5,
                              fontWeight: t == current ? FontWeight.w800 : FontWeight.w600,
                            ),
                        child: Text(_labels[t]!),
                      ),
                      if ((counts[t] ?? 0) > 0) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: t == current ? c.brandGradient : null,
                            color: t == current ? null : c.primaryTint,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            '${counts[t]}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: t == current ? Colors.white : c.primary,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 10.5,
                                ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: 3,
                    width: t == current ? 22 : 0,
                    decoration: BoxDecoration(
                      gradient: c.brandGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// ===== FEED =====

class _FeedTab extends StatelessWidget {
  const _FeedTab();

  @override
  Widget build(BuildContext context) {
    final community = context.watch<CommunityProvider>();
    final posts = community.posts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // No inline composer: writing a post lives on the floating "+", so the
        // feed opens straight into other people's words.
        if (posts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH, vertical: 24),
            child: Center(
              child: Text(
                community.loading ? 'loading the feed…' : 'no posts yet',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
            child: Column(
              // No gap between cards: each one already reserves the space its
              // avatar hangs into.
              children: [for (final post in posts) _PostCard(post: post)],
            ),
          ),
      ],
    );
  }
}

/// The post composer: free text + an optional mood + tag chips. Posts to the
/// backend via [CommunityProvider.createPost] and prepends to the feed.
class _ComposerSheet extends StatefulWidget {
  const _ComposerSheet();

  /// Opens the sheet carrying the live provider across the route boundary, so
  /// a new post lands in the same feed you were just looking at.
  static void open(BuildContext context) {
    final community = context.read<CommunityProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: community,
        child: const _ComposerSheet(),
      ),
    );
  }

  @override
  State<_ComposerSheet> createState() => _ComposerSheetState();
}

class _ComposerSheetState extends State<_ComposerSheet> {
  final _ctrl = TextEditingController();
  EnergyLevel? _mood;
  final Set<String> _tags = {};
  bool _posting = false;

  static const _tagOptions = ['Study', 'Struggles', 'Wins', 'Medication', 'Tips', 'Focus'];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final body = _ctrl.text.trim();
    if (body.isEmpty || _posting) return;
    setState(() => _posting = true);
    try {
      await context.read<CommunityProvider>().createPost(
            body: body,
            mood: _mood?.name,
            tags: _tags.toList(),
          );
      if (mounted) {
        Navigator.of(context).pop();
        Toast.show(context, 'Shared with the community 💛');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _posting = false);
        Toast.show(context, "Couldn't share - is the server running?");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final canPost = _ctrl.text.trim().isNotEmpty && !_posting;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('share with the community', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(18)),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                maxLines: 4,
                minLines: 3,
                maxLength: 1000,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  hintText: "What's on your mind? A win, a struggle, a tip…",
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('how are you feeling?', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final m in EnergyLevel.values)
                  ChoiceChip(
                    selected: _mood == m,
                    label: Text(_moodLabel(m).toLowerCase()),
                    avatar: Icon(m.icon, size: 16, color: m.color(context)),
                    onSelected: (_) => setState(() => _mood = _mood == m ? null : m),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('tags', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in _tagOptions)
                  FilterChip(
                    selected: _tags.contains(t),
                    label: Text('#$t'),
                    onSelected: (on) => setState(() => on ? _tags.add(t) : _tags.remove(t)),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canPost ? _share : null,
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _posting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Share'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
  }
}

/// Relative "2h ago" style stamp from a timestamp.
String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m ago';
  if (d.inHours < 24) return '${d.inHours}h ago';
  return '${d.inDays}d ago';
}

class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final Post post;

  static const _order = [ReactionKind.relate, ReactionKind.support, ReactionKind.proud];

  /// Relate lives in the card's top-right heart, so the footer carries the
  /// other two.
  static const _footer = [ReactionKind.support, ReactionKind.proud];

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final mood = post.mood;
    final moodColor = mood?.color(context) ?? c.text2;
    final reactions = _order.fold<int>(0, (sum, k) => sum + post.countOf(k));

    return Padding(
      // Room for the avatar to hang above the card without being clipped.
      padding: const EdgeInsets.only(bottom: 20),
      child: OmTappable(
        onTap: () => PostCommentsSheet.show(context, post),
        feedback: OmTapFeedback.none,
        pressedScale: 0.995,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              // The card starts below the avatar's centre line, so the face
              // overlaps the corner exactly as the reference does.
              margin: const EdgeInsets.only(top: 26),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: c.shadow.withValues(alpha: context.isDark ? 0.42 : 0.10),
                    blurRadius: 30,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: OmGlass(
                borderRadius: 28,
                blur: 28,
                opacity: context.isDark ? 0.38 : 0.82,
                padding: const EdgeInsets.fromLTRB(20, 34, 18, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                post.authorName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_stamp(post.createdAt)} · ${_ago(post.createdAt)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontSize: 11.5,
                                      color: c.text2,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        // The reference's one round button on the card: a heart
                        // in the top-right. Here it is the real "relate"
                        // reaction, not decoration.
                        _RoundAction(
                          iconName: 'heart',
                          active: post.isActive(ReactionKind.relate),
                          count: post.countOf(ReactionKind.relate),
                          onTap: () => context
                              .read<CommunityProvider>()
                              .toggleReaction(post.id, ReactionKind.relate),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _PostBody(body: post.body),
                    if (post.tags.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in post.tags)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.primaryTint,
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '#$t',
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: c.primary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    // The reference's footer: quiet icons at the two ends, no
                    // rule between them. Support and proud sit left, the
                    // comment thread right.
                    Row(
                      children: [
                        for (final kind in _footer)
                          _IconAction(
                            iconName: kind.iconName,
                            count: post.countOf(kind),
                            active: post.isActive(kind),
                            onTap: () => context.read<CommunityProvider>().toggleReaction(post.id, kind),
                          ),
                        const Spacer(),
                        if (reactions > 0)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              '$reactions ${reactions == 1 ? 'reaction' : 'reactions'}',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2),
                            ),
                          ),
                        _IconAction(
                          iconName: 'message',
                          count: post.commentCount,
                          active: false,
                          onTap: () => PostCommentsSheet.show(context, post),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            // The face hangs off the card's top-left corner, ringed so it reads
            // as sitting above the glass rather than inside it.
            Positioned(
              left: 18,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.surface,
                  boxShadow: [
                    BoxShadow(
                      color: c.shadow.withValues(alpha: context.isDark ? 0.5 : 0.14),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    OmAvatar(
                      userId: post.authorName,
                      fallbackInitial: post.initial,
                      fallbackColor: _hex(post.avatarColor),
                      size: 46,
                    ),
                    // The reference's small coloured disc at the avatar's
                    // corner. Ours carries the mood, so how they felt is
                    // legible before you read a word.
                    if (mood != null)
                      Positioned(
                        right: -2,
                        bottom: -2,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: moodColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.surface, width: 2),
                          ),
                          child: Icon(mood.icon, size: 10, color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Post text with @mentions picked out in the brand colour, as the reference does.
class _PostBody extends StatelessWidget {
  const _PostBody({required this.body});

  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final base = Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 15.5, height: 1.45);
    final spans = <TextSpan>[];
    final pattern = RegExp(r'(@[A-Za-z0-9_.]+)');
    var index = 0;
    for (final m in pattern.allMatches(body)) {
      if (m.start > index) spans.add(TextSpan(text: body.substring(index, m.start)));
      spans.add(TextSpan(
        text: m.group(0),
        style: base?.copyWith(color: c.primary, fontWeight: FontWeight.w700),
      ));
      index = m.end;
    }
    if (index < body.length) spans.add(TextSpan(text: body.substring(index)));

    return RichText(text: TextSpan(style: base, children: spans));
  }
}

/// The circular ghost button in the card's top-right corner.
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.iconName,
    required this.active,
    required this.count,
    required this.onTap,
  });

  final String iconName;
  final bool active;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.85,
      child: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.primaryTint : c.surfaceAlt.withValues(alpha: 0.7),
          shape: BoxShape.circle,
        ),
        child: Icon(
          OmIcons.byName(iconName),
          size: 17,
          color: active ? c.primary : c.text2,
        ),
      ),
    );
  }
}

/// A compact icon + count, replacing the old equal-width button row.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.iconName,
    required this.count,
    required this.active,
    required this.onTap,
  });

  final String iconName;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final color = active ? c.primary : c.text2;
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.85,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(OmIcons.byName(iconName), size: 18, color: color),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "Today 8:59AM" - the reference stamps the exact time under the relative one.
String _stamp(DateTime t) {
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  final ampm = t.hour < 12 ? 'AM' : 'PM';
  return sameDay ? 'Today $h:$m$ampm' : '${t.day}/${t.month} $h:$m$ampm';
}

class _RoomsTab extends StatelessWidget {
  const _RoomsTab();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final fr = context.watch<FocusRoomProvider>();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('focus rooms', style: Theme.of(context).textTheme.titleSmall)),
              GestureDetector(
                onTap: () => _openCreateRoom(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8)],
                  ),
                  child: Text('+ Create', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontSize: 12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (fr.rooms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('loading rooms…', style: Theme.of(context).textTheme.bodySmall)),
            )
          else
            for (final room in fr.rooms)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _RoomTile(room: room, joined: fr.activeRoomId == room.id),
              ),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room, required this.joined});

  final FocusRoom room;
  final bool joined;

  Future<void> _join(BuildContext context) async {
    Haptics.select();
    try {
      _audio.play(AssetSource('audio/join.wav'));
    } catch (_) {}
    context.read<FocusRoomProvider>().joinRoom(room.id);
    // Refresh counts + the global "minds focusing" number after joining.
    try {
      final r = await ApiClient.instance.fetchRooms();
      if (context.mounted) context.read<FocusRoomProvider>().setRooms(r.rooms, r.globalLive);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final iconColor = _hex(room.iconColor);
    final live = room.liveCount > 0;

    return OmTappable(
      pressedScale: 0.985,
      feedback: OmTapFeedback.light,
      onTap: () => _join(context),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: c.shadow.withValues(alpha: context.isDark ? 0.4 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: OmGlass(
          borderRadius: 24,
          blur: 26,
          opacity: context.isDark ? 0.4 : 0.78,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(OmIcons.byName(room.iconName), size: 21, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16),
                        ),
                        const SizedBox(height: 3),
                        // The reference leads with presence: a live dot and a
                        // count, because an empty room is worth knowing about
                        // before you tap.
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                color: live ? const Color(0xFF22C55E) : c.text2.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              live ? '${room.liveCount} focusing' : 'quiet right now',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: live ? c.text : c.text2,
                                  ),
                            ),
                            if (!room.isPublic) ...[
                              const SizedBox(width: 8),
                              Icon(OmIcons.byName('lock'), size: 12, color: c.text2),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // The enter affordance: a filled brand disc, as in the reference.
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: joined ? null : c.brandGradient,
                      color: joined ? c.primaryTint : null,
                      shape: BoxShape.circle,
                      boxShadow: joined
                          ? null
                          : [
                              BoxShadow(
                                color: c.primary.withValues(alpha: 0.35),
                                blurRadius: 12,
                                offset: const Offset(0, 5),
                              ),
                            ],
                    ),
                    child: Icon(
                      joined ? OmIcons.byName('check') : Icons.arrow_outward_rounded,
                      size: 19,
                      color: joined ? c.primary : Colors.white,
                    ),
                  ),
                ],
              ),
              if (live) ...[
                const SizedBox(height: 14),
                _PresenceStack(count: room.liveCount, seed: room.id),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The overlapping faces from the reference. The room API returns a count, not
/// a member list, so these are deterministic stand-ins keyed off the room id:
/// consistent between builds, never implying a specific person is present.
class _PresenceStack extends StatelessWidget {
  const _PresenceStack({required this.count, required this.seed});

  final int count;
  final String seed;

  static const _tints = [
    Color(0xFF6366F1),
    Color(0xFF10B981),
    Color(0xFFEC4899),
    Color(0xFFF59E0B),
    Color(0xFF06B6D4),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final shown = count.clamp(0, 5);
    return SizedBox(
      height: 28,
      child: Stack(
        children: [
          for (var i = 0; i < shown; i++)
            Positioned(
              left: i * 19.0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _tints[(seed.hashCode + i).abs() % _tints.length],
                  shape: BoxShape.circle,
                  border: Border.all(color: c.surface, width: 2),
                ),
              ),
            ),
          if (count > shown)
            Positioned(
              left: shown * 19.0,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.primaryTint,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.surface, width: 2),
                ),
                child: Text(
                  '+${count - shown}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: c.primary,
                        fontWeight: FontWeight.w800,
                        fontSize: 10.5,
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Opens the create-room sheet, scoped to the live [FocusRoomProvider] so the
/// new room appears in everyone's list over the socket.
void _openCreateRoom(BuildContext context) {
  final fr = context.read<FocusRoomProvider>();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ChangeNotifierProvider.value(value: fr, child: const _CreateRoomSheet()),
  );
}

class _CreateRoomSheet extends StatefulWidget {
  const _CreateRoomSheet();

  @override
  State<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends State<_CreateRoomSheet> {
  final _ctrl = TextEditingController();
  bool _public = true;
  bool _creating = false;
  String _icon = 'brain';
  String _ambience = 'cafe';

  static const _icons = ['brain', 'coffee', 'keyboard', 'book', 'moon', 'spark'];
  static const _ambiences = ['cafe', 'silent', 'rain', 'library', 'typing'];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _ctrl.text.trim();
    if (title.isEmpty || _creating) return;
    final fr = context.read<FocusRoomProvider>();
    setState(() => _creating = true);
    try {
      final room = await ApiClient.instance.createRoom(
        title: title,
        iconName: _icon,
        ambience: _ambience,
        isPublic: _public,
      );
      fr.addRoom(room);
      fr.joinRoom(room.id); // host joins their own room immediately
      if (mounted) {
        try {
          _audio.play(AssetSource('audio/join.wav'));
        } catch (_) {}
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _creating = false);
        Toast.show(context, "Couldn't create room - is the server running?");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final canCreate = _ctrl.text.trim().isNotEmpty && !_creating;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('create a focus room', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                maxLength: 40,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  counterText: '',
                  hintText: 'Room name, e.g. Late Night Grind',
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text('icon', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final ic in _icons)
                  ChoiceChip(
                    selected: _icon == ic,
                    label: Icon(OmIcons.byName(ic), size: 18,
                        color: _icon == ic ? c.primary : c.text2),
                    onSelected: (_) => setState(() => _icon = ic),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('ambience', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final a in _ambiences)
                  ChoiceChip(
                    selected: _ambience == a,
                    label: Text(a),
                    onSelected: (_) => setState(() => _ambience = a),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            // Public / private toggle.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Icon(OmIcons.byName(_public ? 'users' : 'lock'), size: 18, color: c.text2),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_public ? 'Public room' : 'Private room',
                            style: Theme.of(context).textTheme.bodyLarge),
                        Text(
                          _public ? 'Anyone can see and join' : 'Join by link only',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  Switch(value: _public, onChanged: (v) => setState(() => _public = v)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: canCreate ? _create : null,
                style: FilledButton.styleFrom(
                  backgroundColor: c.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _creating
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Create & start'),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
        ),
      ),
    );
  }
}

/// ===== GROUPS =====

class _GroupsTab extends StatefulWidget {
  const _GroupsTab();
  @override
  State<_GroupsTab> createState() => _GroupsTabState();
}

class _GroupsTabState extends State<_GroupsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ChatProvider>().loadGroups());
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final suggested = chat.suggestedGroups;
    final mine = chat.myGroups;
    // Lives inside the outer Community ListView, so this is a (non-scrolling)
    // Column - never a nested vertical ListView.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Your groups (joined) ──
          if (mine.isNotEmpty) ...[
            Text('your groups', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            for (final g in mine) ...[
              _GroupRow(group: g, joined: true),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Groups for you (suggested, exactly 5) ──
          Text('groups for you', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          if (suggested.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  chat.loadingGroups
                      ? 'loading groups…'
                      : (mine.isEmpty ? 'no groups yet' : "you're in them all 🎉"),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            )
          else
            for (final g in suggested) ...[
              _GroupRow(group: g, joined: false),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.joined});
  final Group group;
  final bool joined;

  /// Open the group's chat. Resolves a guaranteed-valid conversation id (the
  /// joined group already carries it; otherwise the bug-proof resolver fetches
  /// one) - no more "Could not open chat" from a null/stale id.
  Future<void> _open(BuildContext context) async {
    Haptics.select();
    final chat = context.read<ChatProvider>();
    try {
      final cid = await chat.conversationForGroup(group);
      if (!context.mounted) return;
      ChatScreen.open(
        context,
        id: cid,
        title: group.name,
        iconName: group.iconName,
        iconColor: group.iconColor,
        isGroup: true,
      );
    } catch (e) {
      if (context.mounted) Toast.show(context, 'Could not open chat - retrying may help');
    }
  }

  Future<void> _join(BuildContext context) async {
    Haptics.success();
    try {
      await context.read<ChatProvider>().joinGroup(group);
    } catch (_) {
      if (context.mounted) Toast.show(context, "Couldn't join - try again");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final color = _hexColor(group.iconColor, c.primary);
    return OmCard(
      padding: const EdgeInsets.all(14),
      onTap: joined ? () => _open(context) : () => _join(context),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
            alignment: Alignment.center,
            child: Icon(OmIcons.byName(group.iconName), size: 23, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(group.name, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16)),
                const SizedBox(height: 2),
                Text(group.membersLabel, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
          OmTappable(
            onTap: joined ? () => _open(context) : () => _join(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                gradient: joined ? null : c.brandGradient,
                color: joined ? c.primaryTint : null,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(joined ? 'Open' : 'Join',
                  style: TextStyle(
                      color: joined ? c.primary : Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}

Color _hexColor(String? s, Color fallback) {
  if (s == null) return fallback;
  var h = s.replaceFirst('#', '');
  if (h.length == 6) h = 'FF$h';
  final v = int.tryParse(h, radix: 16);
  return v == null ? fallback : Color(v);
}

/// ===== CHATS =====

class _ChatsTab extends StatefulWidget {
  const _ChatsTab();
  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<ChatProvider>().loadConversations());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final chat = context.watch<ChatProvider>();
    final convos = chat.conversations.where((cv) => !cv.isGroup).toList();
    if (chat.loadingConvos && convos.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('recent messages', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('loading chats…', style: Theme.of(context).textTheme.bodySmall),
              ),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('recent messages', style: Theme.of(context).textTheme.titleSmall)),
              OmTappable(
                pressedScale: 0.95,
                onTap: () {
                  Haptics.select();
                  NewDmSheet.show(context);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    gradient: c.brandGradient,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(OmIcons.byName('edit'), size: 13, color: Colors.white),
                      const SizedBox(width: 5),
                      const Text('New', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (convos.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Text('no chats yet',
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 10),
                    OmTappable(
                      onTap: () {
                        Haptics.select();
                        NewDmSheet.show(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        decoration: BoxDecoration(
                          color: c.primaryTint,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text('Message a friend',
                            style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 13)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            for (final cv in convos) ...[
              _ConvoTile(convo: cv),
              const SizedBox(height: 8),
            ],
        ],
      ),
    );
  }
}

class _ConvoTile extends StatelessWidget {
  const _ConvoTile({required this.convo});
  final ChatConversation convo;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final color = _hexColor(convo.iconColor ?? convo.peerColor, c.primary);
    return OmCard(
      padding: const EdgeInsets.all(12),
      onTap: () {
        Haptics.select();
        ChatScreen.open(
          context,
          id: convo.id,
          title: convo.title,
          iconName: convo.isGroup ? (convo.iconName ?? 'users') : 'user',
          iconColor: convo.iconColor ?? convo.peerColor,
          isGroup: convo.isGroup,
        );
      },
      child: Row(
        children: [
          if (convo.isGroup)
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.16), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Icon(OmIcons.byName(convo.iconName ?? 'users'), size: 20, color: color),
            )
          else
            OmAvatar(
              userId: convo.peerId ?? convo.id,
              fallbackInitial: convo.peerInitial ?? 'U',
              fallbackColor: color,
              size: 48,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(convo.title, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  convo.lastMessage ?? 'No messages yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: convo.unread > 0 ? FontWeight.w600 : FontWeight.w400,
                      ),
                ),
              ],
            ),
          ),
          if (convo.unread > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(color: c.primary, borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Text('${convo.unread}', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }
}
