import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/store_policy.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/speech_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/chat_message.dart';
import '../../providers/coach_provider.dart';
import '../../providers/health_consent_provider.dart';
import '../../providers/memory_provider.dart';
import '../../providers/premium_provider.dart';
import '../../providers/agent_provider.dart';
import '../../widgets/agent_avatar.dart';
import '../../widgets/om_glass.dart';
import '../../widgets/om_push_drawer.dart';
import '../../widgets/om_tappable.dart';
import '../onboarding/health_consent_screen.dart';
import 'agent_picker_screen.dart';
import 'widgets/email_approval_sheet.dart';
import '../../core/services/email_approval.dart';
import '../../widgets/thinking_cloud.dart';

/// "coach" - Mynd, the pocket coach. A calm chat with one-tap prompts for the
/// moments words are hard to find ("i'm stuck", "i'm overwhelmed"…).
///
/// Design is 100% unchanged from the prototype. [_send] and message state route
/// through [CoachProvider] → Groq, reached through our own server.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

/// Free users get this many coach messages per WEEK before the paywall.
///
/// Weekly, not daily, and that is the point rather than the bigger number. A
/// daily cap refuses somebody on the one bad day they actually needed forty
/// messages, then expires unused for the other six. Mirrors WEEKLY_LIMIT in
/// server/src/routes/coach.ts, where the authoritative copy lives.
///
/// Only conversation is metered. The Feed, the scheduling and the app's other
/// reasoning run through the unmetered extract route and are never affected.
const int kCoachWeeklyLimit = 200;

class _CoachScreenState extends State<CoachScreen> {
  static const _prompts = [
    "i'm stuck",
    "i'm overwhelmed",
    'plan my morning',
    'break it down',
    'hype me up',
    'evening reflect',
  ];

  final _controller = TextEditingController();
  final _scroll = ScrollController();

  /// Stops a second sheet going up for the same draft while the first is still
  /// on screen. The provider notifies more than once per pending email.
  bool _approving = false;

  @override
  void initState() {
    super.initState();
    // Opening the coach opens a new conversation. Landing halfway down
    // yesterday afternoon is disorienting, and the old chat is not lost, it is
    // one tap below on the same screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final coach = context.read<CoachProvider>();
      coach.startNewChat();
      // Ask the server how many turns are left before the user finds out by
      // hitting the wall.
      coach.refreshQuota();
      // Whether they have already said "never ask again" about sending mail.
      coach.loadMailPrefs();
      // New mail, and queued messages going out, are spoken by the coach
      // rather than shown as a banner: the promise of the watch is that they
      // hear about it from the voice they asked to watch.
      coach.bindMailWatch();
    });
  }

  /// Put the approval sheet up when the coach has an email waiting.
  ///
  /// Driven from build rather than from the provider, because a provider that
  /// reaches for a BuildContext to show a modal is a provider that cannot be
  /// tested and cannot be shown anywhere else. Here the conversation owns its
  /// own UI and the provider only says what is pending.
  void _maybeAskApproval(CoachProvider coach) {
    final pending = coach.pendingEmail;
    if (pending == null || _approving) return;
    _approving = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _approving = false;
        return;
      }
      final d = await EmailApprovalSheet.open(context, pending);
      _approving = false;
      if (!mounted) return;
      // A sheet that somehow closed without an answer is treated as "do not
      // send". Nothing irreversible should happen on a dismissal.
      coach.resolvePendingEmail(d ?? const EmailDecision.cancel());
    });
  }

  /// What the face should be doing.
  ///
  /// Two distinct states rather than one "busy": waiting on the first token and
  /// watching text arrive feel completely different to sit through, and a
  /// character that keeps thinking while it is visibly talking reads as broken.
  static AgentMood _moodFor(CoachProvider coach) {
    if (coach.isStreaming) return AgentMood.speaking;
    if (coach.isLoading) return AgentMood.thinking;
    return AgentMood.idle;
  }

  void _send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    Haptics.light();
    _controller.clear();
    context.read<CoachProvider>().send(text);
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    _maybeAskApproval(context.watch<CoachProvider>());

    // "Before any coach conversation" is enforced here rather than at the
    // places that navigate to the coach, because the coach is a tab inside an
    // IndexedStack: it is built whether or not anyone routed to it, and three
    // separate entry points reach it. Gating the screen itself is the only
    // version of this that cannot be walked around by a fourth.
    //
    // Watched, so answering rebuilds straight into the chat. Someone who
    // declines is *not* sent back here - the coach below simply runs without
    // the health-related half of its context. See CoachContextBuilder.build.
    //
    // `mustAsk`, not `needsDecision`: the question is only put in front of
    // someone when the server has confirmed there is no answer on file. If the
    // server cannot be reached - or is running a build that predates this
    // endpoint - the coach opens as normal with health context off, rather
    // than showing a consent screen whose answer cannot be recorded and taking
    // the whole feature down with it.
    final consent = context.watch<HealthConsentProvider>();
    if (consent.mustAsk) {
      return HealthConsentScreen(onDecided: (_) {});
    }

    // Every reply is written with the user's memory in hand: who they are,
    // what they are working towards, what they parked, what they have been
    // saying. Watched rather than read once, so an edit takes effect on the
    // next message, not next launch.
    final memory = context.watch<MemoryProvider>();
    context.read<CoachProvider>()
      ..setUserMemory(memory.promptBlock)
      ..setPreferredName(memory.preferredName);

    // Straight to the chat. This used to sit behind a Puter sign-in wall, which
    // meant the coach - the thing the app is for - was unreachable until you
    // registered with a third party. The turn is authenticated and metered by
    // our own server now, so being signed in to OurMynd is the only account
    // anyone needs.
    return _buildChat(context, c);
  }

  Widget _buildChat(BuildContext context, OmColors c) {
    final memory = context.watch<MemoryProvider>();
    final isPremium = context.watch<PremiumProvider>().isPremium;
    final agents = context.watch<AgentProvider>();
    // Who is coaching goes in before the next turn is built. Watched rather
    // than read once, so changing agent or nudging a slider takes effect on the
    // next message rather than at next launch.
    context.read<CoachProvider>()
      ..setAgentBlock(agents.promptBlock)
      ..setAgentName(agents.agent.name);
    return Consumer<CoachProvider>(
      builder: (context, coach, _) {
        // Free tier: after the daily message budget the composer locks behind
        // the paywall. Premium unlocks it entirely.
        //
        // The server's answer wins where we have one. The device counter is
        // kept as a fallback for the offline case, but it is no longer the
        // thing that decides - it could be reset by clearing app data, which
        // made the cap advisory. See CoachProvider.refreshQuota.
        // A refusal from the server locks the composer whatever the local
        // premium flag says. The two can disagree - an entitlement that has
        // lapsed or not yet synced leaves isPremium true here while the server
        // says no - and when they did, the composer stayed open, every send
        // was refused, and the message vanished with no explanation anywhere.
        // The server is the authority on whether a turn is allowed.
        // The server's refusal is the authority; the device counter is only a
        // rough offline guard. It counts a day against a weekly allowance, so
        // it can never be more permissive than the server - only slower to
        // notice - which is the safe direction for a fallback to be wrong in.
        final locked = coach.limitReached ||
            (!isPremium && coach.messagesSentToday >= kCoachWeeklyLimit);
        // Auto-scroll whenever a new token arrives.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (coach.isStreaming) _scrollToEnd();
        });

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(
          children: [
            // Messenger-style header: back to the previous tab, Mynd's avatar
            // with a live "active" dot, name + subtitle, and the connect chip.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  8, AppSpacing.screenTop, AppSpacing.screenH, 8),
              child: Row(
                children: [
                  // The drawer, always. This is the chat tab: the panel is the
                  // only route to side chats and to Profile, so the control has
                  // one job.
                  //
                  // It used to be `if (Navigator.canPop())` show a back arrow
                  // instead, which sounds reasonable and is not: canPop is a
                  // live reading of the stack, so the icon changed the instant
                  // anything at all was pushed over this screen. Tapping the
                  // quota pill flipped the hamburger into a back arrow, which
                  // looked like the sidebar glitching, because in a sense it
                  // was. Nothing pushes CoachScreen anyway - the tab and the
                  // route are its only two call sites, and the route already
                  // asks for no back button - so the branch could only ever
                  // fire by accident.
                  _DrawerButton(
                      onTap: () => OmPushDrawer.of(context)?.open()),
                  const SizedBox(width: 4),
                  // The agent's face, and it is a button: tapping it is the
                  // fastest route to switching who you are talking to.
                  //
                  // The thinking cloud sits over the top of the head and is
                  // allowed to overflow the row, which is why the Stack is
                  // unclipped and the avatar keeps its own 44px footprint:
                  // reserving space for the cloud would shift the whole header
                  // every time the coach started composing.
                  Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.topCenter,
                    children: [
                      AgentAvatar(
                        agent: agents.agent,
                        size: 44,
                        mood: _moodFor(coach),
                        onTap: () => AgentPickerScreen.open(context),
                      ),
                      Positioned(
                        top: -30,
                        child: ThinkingCloud(
                          visible: coach.isLoading && !coach.isStreaming,
                          colour: agents.agent.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(agents.agent.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontSize: 19, fontWeight: FontWeight.w800)),
                        const _CoachSubtitle(),
                      ],
                    ),
                  ),
                  // History and new chat used to sit here. Both are in the side
                  // panel now, which is one tap away on the left of this very
                  // row, and a control that exists twice on one screen is a
                  // control somebody has to think about twice.
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                // Drag the conversation, lose the keyboard. The expected
                // gesture in every chat app, and the one people reach for
                // first when the keyboard is covering what they want to read.
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.xl,
                  AppSpacing.screenH,
                  AppSpacing.md,
                ),
                // Before the first exchange the screen is mostly empty, so it
                // leads with the orb and the question instead of one lonely
                // bubble in the corner.
                itemCount: coach.messages.length +
                    (coach.isLoading && !coach.isStreaming ? 1 : 0) +
                    (coach.messages.length <= 1
                        ? (memory.needsName ? 2 : 1)
                        : 0),
                itemBuilder: (context, i) {
                  if (coach.messages.length <= 1) {
                    if (i == 0) {
                      // The orb, then one way back into everything before it.
                      // Just the hero. The way back to an old chat is the
                      // side panel, and this was the third place it appeared.
                      return const _CoachHero();
                    }
                    i -= 1;
                    // Before anything else is asked of them, the one question
                    // we cannot answer ourselves.
                    if (memory.needsName) {
                      if (i == 0) return const _NameCard();
                      i -= 1;
                    }
                  }
                  if (i == coach.messages.length) {
                    return const _TypingBubble();
                  }
                  return _ChatBubble(message: coach.messages[i]);
                },
              ),
            ),
            // SafeArea alone, and nothing added to it.
            //
            // The shell sets extendBody: true, and Flutter folds the bottom bar
            // height INTO this body's MediaQuery bottom padding so content can
            // clear it. So SafeArea already steps over the whole bar plus the
            // home indicator. Every version of this that also added
            // navBarHeight was counting the bar twice, which is where the band
            // of dead page between the composer and the bar came from.
            SafeArea(
              bottom: true,
              child: Padding(
                // Clear the nav bar, which now runs underneath this screen.
                // The shell uses extendBody so the glass bar has something to
                // blur, which means the composer has to reserve that height
                // itself or it sits behind the bar. The bar is hidden while the
                // keyboard is up, so the room is given back then rather than
                // leaving a strip of dead space above the keyboard.
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  0,
                  AppSpacing.screenH,
                  // SafeArea above has already stepped over the whole bar, so
                  // this is only the breathing room between the composer and
                  // the glyph row - which the reference has, rather than the
                  // two being welded together.
                  MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (locked)
                      const _LimitReachedCard()
                    else ...[
                      // Said before the wall, not at it. Silence followed by a
                      // hard stop is what made running out feel like a bug.
                      if (coach.quotaRunningLow) const _QuotaWarning(),
                      // Only show quick prompts if the user hasn't sent a message
                      // yet (messages.length <= 1 = only the welcome message).
                      if (coach.messages.length <= 1) ...[
                        SizedBox(
                          height: 42,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _prompts.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) => _PromptChip(
                              label: _prompts[i],
                              urgent: i == 0,
                              onTap: () => _send(_prompts[i]),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                      _CoachInput(controller: _controller, onSend: _send),
                    ],
                  ],
                ),
              ),
            ), // Close SafeArea
          ],
          ),
        );
      },
    );
  }
}

/// "12 messages left this week." Shown only near the end of the allowance.
class _QuotaWarning extends StatelessWidget {
  const _QuotaWarning();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final coach = context.watch<CoachProvider>();
    final left = coach.remainingToday;
    if (left == null) return const SizedBox.shrink();

    // Not a button on a build that cannot sell. The tap pushed the paywall
    // route, which on iOS is not registered, so onGenerateRoute fell through to
    // its default and pushed a SECOND AppShell on top of the first. Nothing
    // appeared to happen - it is the same app - except that the stack now had
    // something to pop, which is what turned the drawer icon into a back arrow.
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: OmTappable(
        onTap: StorePolicy.canSell
            ? () => Navigator.of(context).pushNamed(AppRoutes.paywall)
            : null,
        feedback: OmTapFeedback.light,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: c.attention.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.info_outline_rounded, size: 15, color: c.attention),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  left <= 0
                      ? 'No messages left this week'
                      : '$left message${left == 1 ? '' : 's'} left this week',
                  style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The hamburger. Its own widget so the header row stays readable, and so the
/// tap target is the full 46px the rest of the app's round controls use.
class _DrawerButton extends StatelessWidget {
  const _DrawerButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.light,
      child: Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        child: Icon(OmIcons.byName('menu'), size: 22, color: c.text),
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

/// The line under "Mynd".
///
/// This was a model picker: eight Puter model names in a sheet, chosen on the
/// device. The coach runs on Groq through our own server now, which picks the
/// model itself, so a picker here would offer a choice that changes nothing.
/// What it said about availability was the useful half, so that is what stays.
class _CoachSubtitle extends StatelessWidget {
  const _CoachSubtitle();

  @override
  Widget build(BuildContext context) => Text(
        'always here',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodySmall,
      );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final mine = message.fromUser;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(20),
      topRight: const Radius.circular(20),
      bottomLeft: Radius.circular(mine ? 20 : 7),
      bottomRight: Radius.circular(mine ? 7 : 20),
    );

    final text = Text(
      message.text.isEmpty && message.isStreaming ? '…' : message.text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: mine ? Colors.white : c.text,
            height: 1.45,
            fontWeight: mine ? FontWeight.w500 : FontWeight.w400,
          ),
    );

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        child: mine
            ? Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: c.brandGradient,
                  borderRadius: radius,
                  boxShadow: [
                    BoxShadow(
                      color: c.primary.withValues(alpha: 0.28),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: text,
              )
            // Mynd's replies are glass: they sit on the surface rather than
            // competing with the user's own words.
            : ClipRRect(
                borderRadius: radius,
                child: OmGlass(
                  borderRadius: 20,
                  blur: 22,
                  opacity: context.isDark ? 0.42 : 0.8,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: text,
                ),
              ),
      ),
    );
  }
}

/// The opening state: the orb, a greeting, and nothing else to read.
///
/// Laid out like the reference - the blob carries the whole top of the screen
/// and the question sits under it in two lines, the second one heavier, so the
/// eye lands on "what's going on?" rather than on a wall of chrome.
class _CoachHero extends StatelessWidget {
  const _CoachHero();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final name = context.watch<MemoryProvider>().preferredName;
    final greeting = (name != null && name.isNotEmpty) ? 'hey $name,' : 'hey,';
    final agent = context.watch<AgentProvider>().agent;

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 30),
      child: Column(
        children: [
          AgentAvatar(
            agent: agent,
            size: 128,
            mood: AgentMood.idle,
            onTap: () => AgentPickerScreen.open(context),
          ),
          const SizedBox(height: 22),
          // Who they are, said out loud, with the way to change it right there.
          // The face alone does not tell somebody that the personality behind
          // it is a choice.
          OmTappable(
            onTap: () => AgentPickerScreen.open(context),
            feedback: OmTapFeedback.light,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              // The tagline is Flexible and the name is not, because the name
              // is the part that must never be cut. Unbounded, this Row
              // overflowed by 233 pixels on a phone - a tagline is a sentence,
              // and every one of them is longer than a pill is wide. It is the
              // first screen a new account sees, so the overflow stripes were
              // on the first thing anybody looked at.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(agent.name,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      agent.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: c.text2, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(OmIcons.byName('chevR'), size: 15, color: c.text2),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            greeting,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  height: 1.25,
                  color: c.text2,
                ),
          ),
          Text(
            "what's going on?",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
          ),
        ],
      ),
    );
  }
}

/// Asked once, the first time they open the coach: what should I call you?
///
/// The alternative was guessing from the account name, which is how the coach
/// spent months calling everyone Sam. A name is the one piece of context you
/// cannot infer, so it is the one thing worth interrupting for, exactly once.
class _NameCard extends StatefulWidget {
  const _NameCard();

  @override
  State<_NameCard> createState() => _NameCardState();
}

class _NameCardState extends State<_NameCard> {
  final _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    final v = _field.text.trim();
    if (v.isEmpty) return;
    Haptics.success();
    final memory = context.read<MemoryProvider>();
    memory.setPreferredName(v);
    context.read<CoachProvider>().setPreferredName(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: OmGlass(
        borderRadius: 22,
        blur: 24,
        opacity: context.isDark ? 0.40 : 0.80,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('what should I call you?',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text('whatever you actually go by. I will stick to it.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: c.text2)),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: TextField(
                      controller: _field,
                      textCapitalization: TextCapitalization.words,
                      onSubmitted: (_) => _save(),
                      style: Theme.of(context).textTheme.bodyMedium,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        hintText: 'your name',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OmTappable(
                  onTap: _save,
                  feedback: OmTapFeedback.none,
                  pressedScale: 0.9,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      gradient: c.brandGradient,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: const Text("that's me",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 13)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            // Not answering is an answer, and it stops the question coming back.
            OmTappable(
              onTap: () {
                Haptics.light();
                context.read<MemoryProvider>().declineName();
                context.read<CoachProvider>().setPreferredName('');
              },
              feedback: OmTapFeedback.none,
              pressedScale: 0.96,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text('skip this',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: c.text2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Thinking. The agent's own face is the indicator: it is already animated,
/// so it says "someone is there" better than the words "Mynd is typing" ever
/// did, and it is the same character that is about to answer.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Row(
        children: [
          AgentAvatar(
            agent: context.watch<AgentProvider>().agent,
            size: 26,
            mood: AgentMood.thinking,
            showRing: false,
          ),
          const SizedBox(width: 10),
          Text(
            'thinking…',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2),
          ),
        ],
      ),
    );
  }
}

class _PromptChip extends StatelessWidget {
  const _PromptChip({
    required this.label,
    required this.urgent,
    required this.onTap,
  });

  final String label;
  final bool urgent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: urgent ? c.attention.withValues(alpha: 0.14) : c.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: urgent
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ],
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (urgent) ...[
              Icon(OmIcons.byName('buoy'), size: 14, color: c.attention),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: urgent ? c.attention : c.text,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown in place of the composer once a free user hits the message cap.
class _LimitReachedCard extends StatelessWidget {
  const _LimitReachedCard();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.lock_rounded, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Text('Message limit reached',
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            StorePolicy.canSell
                ? 'Free includes $kCoachWeeklyLimit messages a week, and they '
                    'reset every Monday. Plus raises it to 1,000 and Pro '
                    'removes the cap.'
                : 'That is $kCoachWeeklyLimit messages this week. They reset '
                    'every Monday, and everything else in the app keeps '
                    'working in the meantime.',
            style:
                Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2, height: 1.4),
          ),
          // The button only exists where there is something to buy.
          //
          // It used to be shown unconditionally, and on iOS it pushed a route
          // that is deliberately not registered there - so it silently stacked
          // a second copy of the whole app instead of opening anything. An
          // upgrade button that does nothing is worse than no button: it reads
          // as the app being broken at the exact moment somebody is being
          // asked to pay.
          if (StorePolicy.canSell) ...[
            const SizedBox(height: 14),
            OmTappable(
              onTap: () {
                Haptics.medium();
                Navigator.of(context).pushNamed(AppRoutes.paywall);
              },
              feedback: OmTapFeedback.none,
              pressedScale: 0.97,
              child: Container(
                width: double.infinity,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: c.brandGradient,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: const Text('Upgrade to Premium',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The send key.
///
/// It was a gradient square with a coloured drop shadow, which is three effects
/// doing one job and read as a decal stuck on the composer. A flat circle in
/// the brand colour is what a send key looks like in every app anybody has used
/// this decade, and the circle matches the round controls in the header rather
/// than introducing a fourth corner radius.
///
/// It also goes quiet when there is nothing to send, which the old one did not:
/// a permanently bright button on an empty field is an invitation to press
/// something that cannot do anything.
class _SendKey extends StatelessWidget {
  const _SendKey({required this.controller, required this.onSend});

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // Listens to the field itself rather than lifting the text into the
    // screen's state, so typing does not rebuild the message list on every
    // keystroke.
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        final ready = value.text.trim().isNotEmpty;
        return Semantics(
          label: 'send',
          button: true,
          enabled: ready,
          child: OmTappable(
            onTap: ready ? () => onSend(controller.text) : null,
            enabled: ready,
            feedback: OmTapFeedback.none,
            pressedScale: 0.9,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOut,
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: ready ? c.primary : c.text2.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.arrow_upward_rounded,
                size: 20,
                color: ready ? Colors.white : c.text2,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CoachInput extends StatelessWidget {
  const _CoachInput({required this.controller, required this.onSend});

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: context.isDark ? 0.45 : 0.10),
            blurRadius: 20,
            offset: const Offset(0, 6),
          )
        ],
      ),
      child: OmGlass(
        borderRadius: AppRadius.pill,
        blur: 26,
        opacity: context.isDark ? 0.45 : 0.86,
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: onSend,
                // Flutter does not dismiss the keyboard on a tap elsewhere on
                // a touch device - the default only does that on desktop - so
                // without this the keyboard stayed up over everything it was
                // covering, and tapping the drawer, the agent's face or
                // another tab did nothing about it.
                onTapOutside: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
                minLines: 1,
                maxLines: 4,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: c.text, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'ask anything…',
                  hintStyle: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: c.text2, fontSize: 15),
                  border: InputBorder.none,
                  isCollapsed: true,
                ),
              ),
            ),
            const SizedBox(width: 2),
            // Speak instead of type. Same destination either way: the
            // transcript lands in the field, so it can be read and corrected
            // before it is sent rather than going straight off as whatever the
            // transcriber heard.
            _MicKey(controller: controller),
            const SizedBox(width: 2),
            _SendKey(controller: controller, onSend: onSend),
          ],
        ),
      ),
    );
  }
}

/// Dictation for the composer.
///
/// Records while held open, transcribes on the second tap and appends the
/// result to whatever is already typed. It deliberately does NOT send: the
/// transcript is a draft like any other, and a mis-heard sentence that posts
/// itself is a worse outcome than one you can fix first.
class _MicKey extends StatefulWidget {
  const _MicKey({required this.controller});

  final TextEditingController controller;

  @override
  State<_MicKey> createState() => _MicKeyState();
}

enum _Mic { idle, listening, working }

class _MicKeyState extends State<_MicKey> {
  final _stt = SpeechService.instance;
  _Mic _phase = _Mic.idle;
  double _level = 0;

  @override
  void dispose() {
    // Leaving the screen mid-sentence must not leave the mic open.
    if (_phase == _Mic.listening) unawaited(_stt.cancel());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_phase == _Mic.working) return;

    if (_phase == _Mic.listening) {
      setState(() => _phase = _Mic.working);
      final text = await _stt.stopAndTranscribe();
      if (!mounted) return;
      setState(() {
        _phase = _Mic.idle;
        _level = 0;
      });
      final clean = text.trim();
      if (clean.isEmpty) {
        Toast.show(context, "Didn't catch that. Try again?");
        return;
      }
      // Appended, not replaced: somebody who typed half a sentence and then
      // spoke the rest should end up with both.
      final existing = widget.controller.text.trimRight();
      final joined = existing.isEmpty ? clean : '$existing $clean';
      widget.controller.value = TextEditingValue(
        text: joined,
        selection: TextSelection.collapsed(offset: joined.length),
      );
      Haptics.success();
      return;
    }

    Haptics.medium();
    final ok = await _stt.startRecording(
      onLevel: (l) {
        if (mounted && _phase == _Mic.listening) {
          setState(() => _level = _level * 0.6 + l * 0.4);
        }
      },
    );
    if (!mounted) return;
    if (!ok) {
      // The service's own words: a missing grant, a refused one and a recorder
      // that would not open are three different problems with three different
      // fixes, and "check your permissions" is wrong for two of them.
      Toast.show(context, _stt.lastError ?? 'Microphone unavailable.');
      if (_stt.micBlockedInSettings) await _stt.openMicSettings();
      return;
    }
    setState(() => _phase = _Mic.listening);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final listening = _phase == _Mic.listening;
    return Semantics(
      button: true,
      label: listening ? 'stop dictating' : 'dictate a message',
      child: OmTappable(
        onTap: _toggle,
        feedback: OmTapFeedback.none,
        pressedScale: 0.9,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            // While listening it swells gently with the level, so the button
            // itself says the mic is open rather than leaving somebody talking
            // at a screen that looks idle.
            color: listening
                ? c.accent.withValues(alpha: 0.22 + (_level.clamp(0, 1) * 0.5))
                : Colors.transparent,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: _phase == _Mic.working
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: c.text2),
                )
              : Icon(
                  listening ? Icons.stop_rounded : OmIcons.byName('mic'),
                  size: listening ? 22 : 19,
                  color: listening ? c.accent : c.text2,
                ),
        ),
      ),
    );
  }
}
