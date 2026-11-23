import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/pro_features.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/feed_post.dart';
import '../../providers/coach_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/premium_provider.dart';
import '../../providers/nav_provider.dart';
import '../../providers/agent_provider.dart';
import '../../widgets/agent_avatar.dart';
import '../../widgets/om_tappable.dart';
import '../home/widgets/motivation_card.dart';
import 'widgets/feed_instructions_card.dart';

/// The Feed: what the coach thought was worth bringing you, by day-part.
///
/// Editions stack downward and stay on the device, so the screen is something
/// you can scroll back through rather than a list that resets every time it is
/// opened. The instructions that produce it are one tap away at the top, not
/// buried in Settings, because they are the feed rather than a preference
/// about it.
class FeedScreen extends StatefulWidget {
  const FeedScreen({super.key});

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  bool _editing = false;

  bool _canCustomise(BuildContext context) => ProFeatures.canCustomiseFeed(
      premium: context.read<PremiumProvider>().isPremium);

  @override
  void initState() {
    super.initState();
    // After the first frame: the provider notifies while loading, and calling
    // it during build would rebuild the tree it is being built for.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<FeedProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final feed = context.watch<FeedProvider>();

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _FeedHeader(
              editing: _editing,
              locked: !_canCustomise(context),
              onToggleEdit: () {
                // Rewriting the instructions is what the feed is generated
                // from, so it is the whole of "customise your feed". A free
                // user still gets a feed, built from the default brief; what
                // Pro buys is saying what it should be about.
                if (!_canCustomise(context)) {
                  Haptics.light();
                  Navigator.of(context).pushNamed(AppRoutes.paywall);
                  return;
                }
                Haptics.light();
                setState(() => _editing = !_editing);
              },
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => context.read<FeedProvider>().refresh(),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenH,
                    AppSpacing.sm,
                    AppSpacing.screenH,
                    AppSpacing.screenBottom,
                  ),
                  children: [
                    if (_editing) ...[
                      FeedInstructionsCard(
                        // Keyed on the text so reopening the editor after a
                        // save starts from what was saved, not from the field
                        // state of the last edit.
                        key: ValueKey(feed.instructions),
                        initial: feed.instructions,
                        onCancel: () => setState(() => _editing = false),
                        onSave: (text) {
                          setState(() => _editing = false);
                          context.read<FeedProvider>().saveInstructions(text);
                          Toast.show(context, 'rewriting your feed…');
                        },
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],

                    // The day's line. The one thing here that is about the
                    // reader rather than about the world, so it stays at the
                    // top whether or not it has been set up: its empty state
                    // is the way in to setting it up.
                    const MotivationCard(),
                    const SizedBox(height: AppSpacing.lg),

                    if (feed.writing) const _WritingNote(),

                    if (feed.editions.isEmpty && feed.loaded && !feed.writing)
                      _FeedEmpty(
                        problem: feed.problem,
                        onEdit: () {
                          if (!_canCustomise(context)) {
                            Navigator.of(context).pushNamed(AppRoutes.paywall);
                            return;
                          }
                          setState(() => _editing = true);
                        },
                        onRetry: () => context.read<FeedProvider>().refresh(),
                      ),

                    for (final edition in feed.editions) ...[
                      Padding(
                        padding: const EdgeInsets.only(
                            top: AppSpacing.sm, bottom: AppSpacing.lg),
                        child: Text(
                          edition.label,
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      for (final post in edition.posts) _PostCard(post: post),
                    ],
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

/// Mynd's face, its name, and the way into the instructions.
class _FeedHeader extends StatelessWidget {
  const _FeedHeader({
    required this.editing,
    required this.locked,
    required this.onToggleEdit,
  });

  final bool editing;

  /// Still tappable when locked - it routes to the paywall rather than doing
  /// nothing. A control that silently ignores a tap reads as broken, and the
  /// person tapping it is the one considering paying.
  final bool locked;

  final VoidCallback onToggleEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, AppSpacing.sm),
      // Full width, and that is load-bearing. A Stack sizes itself to its
      // biggest non-positioned child, so without this it shrank to the width of
      // the name pill and `right: 0` put the instructions button on top of the
      // name instead of at the edge of the screen.
      child: SizedBox(
        width: double.infinity,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AgentAvatar(
                  agent: context.watch<AgentProvider>().agent,
                  size: 72,
                  mood: AgentMood.idle,
                ),
                // The pill overlaps the face's lower edge, as in the reference,
                // rather than sitting under it as a separate label.
                Transform.translate(
                  offset: const Offset(0, -12),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      context.watch<AgentProvider>().agent.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              right: 0,
              child: Semantics(
                label: locked
                    ? 'feed instructions, included with Pro'
                    : 'feed instructions',
                button: true,
                child: OmTappable(
                  onTap: onToggleEdit,
                  feedback: OmTapFeedback.none,
                  pressedScale: 0.9,
                  child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: editing
                          ? c.primary.withValues(alpha: 0.16)
                          : c.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      OmIcons.byName(
                          locked ? 'lock' : (editing ? 'close' : 'sliders')),
                      size: 20,
                      color: editing
                          ? c.primary
                          : locked
                              ? c.text2
                              : c.text,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One written post: the glyph, the sentence, the prose, and what you can do
/// about it.
class _PostCard extends StatelessWidget {
  const _PostCard({required this.post});

  final FeedPost post;

  Future<void> _openSource(BuildContext context) async {
    final url = post.linkUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) Toast.show(context, "couldn't open that one");
  }

  /// Reply takes you to the coach with the post already on the table, because
  /// a reply to a feed nobody else reads is a conversation with Mynd. Starting
  /// a fresh thread rather than appending keeps the main chat about the day.
  Future<void> _discuss(BuildContext context) async {
    Haptics.light();
    final coach = context.read<CoachProvider>();
    context.read<NavProvider>().select(AppTab.coach);
    await coach.startNewChat();
    await coach.send(
      'About something in my feed - "${post.title}". ${post.body}\n\n'
      'What do you make of it?',
    );
  }

  /// Where this came from, and a way to go and read it.
  ///
  /// The (i) used to explain the feed's own machinery, which is the answer to a
  /// question nobody was asking. What somebody wants from an information button
  /// on a news card is the provenance: who wrote this, and can I see the
  /// original. A post is our summary of somebody else's reporting, so naming
  /// them and linking out is the honest thing as well as the useful one.
  void _source(BuildContext context) {
    Haptics.light();
    final c = context.omColors;
    final host = _host(post.linkUrl);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: c.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl, 0, AppSpacing.xl, AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Source',
                  style: Theme.of(sheet)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(OmIcons.byName('newspaper'),
                        size: 20, color: c.primary),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          post.source?.isNotEmpty == true
                              ? post.source!
                              : (host ?? 'Unknown publisher'),
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                        if (host != null && host != post.source) ...[
                          const SizedBox(height: 2),
                          Text(host,
                              style: TextStyle(color: c.text2, fontSize: 13)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'This post is your coach\'s summary of their reporting. The '
                'article itself is theirs.',
                style: TextStyle(color: c.text2, height: 1.45, fontSize: 13),
              ),
              if (post.linkUrl != null && post.linkUrl!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xl),
                OmTappable(
                  onTap: () {
                    Navigator.of(sheet).pop();
                    _openSource(context);
                  },
                  feedback: OmTapFeedback.light,
                  child: Container(
                    height: 52,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.primary,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text('Read the original',
                        style: TextStyle(
                            color: OmColors.onFill(c.primary),
                            fontWeight: FontWeight.w700,
                            fontSize: 16)),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Your feed instructions decide what gets written up. Change '
                'them with the control at the top of the feed.',
                style: TextStyle(color: c.text2, height: 1.45, fontSize: 12.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The publisher's domain, which is the most honest name we have when the
  /// source field is empty.
  static String? _host(String? url) {
    if (url == null || url.isEmpty) return null;
    final u = Uri.tryParse(url);
    if (u == null || u.host.isEmpty) return null;
    return u.host.replaceFirst(RegExp(r'^www\.'), '');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 12),
                child: Text(post.emoji, style: const TextStyle(fontSize: 26)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      post.title,
                      style: t.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800, height: 1.25),
                    ),
                    const SizedBox(height: 6),
                    _PostBody(post: post, onOpen: () => _openSource(context)),
                    if (post.highlight != null) ...[
                      const SizedBox(height: AppSpacing.lg),
                      _HighlightBlock(highlight: post.highlight!),
                    ],

                    // The picture sits inside the text column, so its left
                    // edge lines up with the headline and the prose rather
                    // than starting back under the emoji. Full width across
                    // the card left it hanging a gutter further left than
                    // every other thing in the post, which is what made it
                    // look pasted on.
                    //
                    // After the writing, not before it: this feed is the coach
                    // telling you something, so the sentence it wrote is what
                    // you meet first. It also means a slow or missing image
                    // can never push the writing down the screen.
                    if (post.imageUrl != null && post.imageUrl!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            post.imageUrl!,
                            fit: BoxFit.cover,
                            // A publisher's image can 404 or refuse to be
                            // hotlinked. The post reads perfectly without one,
                            // so a failure collapses the picture rather than
                            // leaving a broken glyph under real writing.
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                            loadingBuilder: (ctx, child, progress) =>
                                progress == null
                                    ? child
                                    : Container(color: c.surfaceAlt),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _ActionIcon(
                icon: 'heart',
                label: 'like this',
                filled: post.liked,
                onTap: () {
                  Haptics.light();
                  context.read<FeedProvider>().toggleLike(post);
                },
              ),
              const SizedBox(width: AppSpacing.lg),
              OmTappable(
                onTap: () => _discuss(context),
                feedback: OmTapFeedback.none,
                pressedScale: 0.95,
                child: Row(
                  children: [
                    Icon(OmIcons.byName('message'), size: 21, color: c.text2),
                    const SizedBox(width: 8),
                    Text('Discuss',
                        style: t.titleMedium?.copyWith(
                            color: c.text, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const Spacer(),
              _ActionIcon(
                icon: 'info',
                label: 'where this came from',
                filled: false,
                onTap: () => _source(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Divider(height: 1, color: c.border.withValues(alpha: 0.6)),
        ],
      ),
    );
  }
}

/// The prose, with the phrase the writer chose turned into the link.
///
/// Stateful only because a [TapGestureRecognizer] has to be disposed. Leaking
/// one per card would be a leak per scroll, on the screen people scroll most.
class _PostBody extends StatefulWidget {
  const _PostBody({required this.post, required this.onOpen});

  final FeedPost post;
  final VoidCallback onOpen;

  @override
  State<_PostBody> createState() => _PostBodyState();
}

class _PostBodyState extends State<_PostBody> {
  TapGestureRecognizer? _tap;

  @override
  void dispose() {
    _tap?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final base = Theme.of(context)
        .textTheme
        .bodyLarge
        ?.copyWith(color: c.text, height: 1.5);

    final body = widget.post.body;
    final phrase = widget.post.linkText;
    final url = widget.post.linkUrl;

    // No link, or a phrase the writer did not actually use: plain text. A
    // "read more" bolted onto the end when the model's linkText missed would
    // read as boilerplate the writer never wrote.
    final at = (phrase == null || phrase.isEmpty || url == null || url.isEmpty)
        ? -1
        : body.indexOf(phrase);
    if (at < 0) return Text(body, style: base);

    _tap ??= TapGestureRecognizer()..onTap = widget.onOpen;

    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: body.substring(0, at)),
          TextSpan(
            text: phrase,
            style: base?.copyWith(
              color: c.primary,
              decoration: TextDecoration.underline,
              decorationColor: c.primary,
              fontWeight: FontWeight.w600,
            ),
            recognizer: _tap,
          ),
          TextSpan(text: body.substring(at + phrase!.length)),
        ],
      ),
    );
  }
}

/// The one figure the post is about, in the app's own accent.
class _HighlightBlock extends StatelessWidget {
  const _HighlightBlock({required this.highlight});

  final FeedHighlight highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.xl),
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Column(
        children: [
          Text(
            highlight.label.toUpperCase(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.text2,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            highlight.value,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: c.primary,
                ),
          ),
          if (highlight.caption != null && highlight.caption!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              highlight.caption!,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.text2, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}

/// A glyph-only action. Labelled, because an unlabelled icon button is a
/// button that announces itself as nothing at all.
class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Semantics(
      label: label,
      button: true,
      child: OmTappable(
        onTap: onTap,
        feedback: OmTapFeedback.none,
        pressedScale: 0.88,
        child: Icon(
          filled ? OmIcons.solid(icon) : OmIcons.byName(icon),
          size: 22,
          // A liked post is marked in the app's accent, not in red: the heart is
          // a bookmark here, and nothing about it leaves the phone.
          color: filled ? c.primary : c.text2,
        ),
      ),
    );
  }
}

/// Shown while the coach is composing an edition. Says what is happening
/// rather than spinning, because this one genuinely takes a few seconds.
class _WritingNote extends StatelessWidget {
  const _WritingNote();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
          ),
          const SizedBox(width: 12),
          Text('writing your feed…',
              style: TextStyle(color: c.text2, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _FeedEmpty extends StatelessWidget {
  const _FeedEmpty({
    required this.problem,
    required this.onEdit,
    required this.onRetry,
  });

  /// What went wrong, when something did. Shown rather than swallowed: "no
  /// feed because the source is down" and "no feed because you have not said
  /// what you want" need completely different things from the reader.
  final String? problem;
  final VoidCallback onEdit;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        children: [
          Icon(OmIcons.byName('newspaper'), size: 26, color: c.text2),
          const SizedBox(height: 10),
          Text(
            'Nothing written yet.',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            problem ??
                'Tell your feed what it should cover and your coach will '
                    'write the next edition against it.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text2, height: 1.4),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _SmallButton(label: 'Edit instructions', onTap: onEdit),
              const SizedBox(width: AppSpacing.md),
              _SmallButton(label: 'Try again', onTap: onRetry),
            ],
          ),
        ],
      ),
    );
  }
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: c.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Text(label,
            style: TextStyle(color: c.primary, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
