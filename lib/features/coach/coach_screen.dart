import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/puter_service.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/chat_message.dart';
import '../../providers/coach_provider.dart';
import '../../providers/memory_provider.dart';
import '../../widgets/fluid_orb.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_glass.dart';
import '../../widgets/om_tappable.dart';
import 'coach_voice_screen.dart';
import 'puter_gate.dart';

/// "coach" - Mynd, the pocket coach. A calm chat with one-tap prompts for the
/// moments words are hard to find ("i'm stuck", "i'm overwhelmed"…).
///
/// Design is 100% unchanged from the prototype. The only difference is that
/// [_send] and message state now route through [CoachProvider] → Groq.
class CoachScreen extends StatefulWidget {
  const CoachScreen({super.key});

  @override
  State<CoachScreen> createState() => _CoachScreenState();
}

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

  @override
  void initState() {
    super.initState();
    // Opening the coach opens a new conversation. Landing halfway down
    // yesterday afternoon is disorienting, and the old chat is not lost, it is
    // one tap below on the same screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CoachProvider>().startNewChat();
    });
  }

  void _send(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return;
    Haptics.light();
    _controller.clear();
    context.read<CoachProvider>().send(text);
    _scrollToEnd();
  }

  void _openVoice() {
    Haptics.medium();
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const CoachVoiceScreen()));
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

    // Every reply is written with the user's memory in hand: who they are,
    // what they are working towards, what they parked, what they have been
    // saying. Watched rather than read once, so an edit takes effect on the
    // next message, not next launch.
    final memory = context.watch<MemoryProvider>();
    context.read<CoachProvider>()
      ..setUserMemory(memory.promptBlock)
      ..setPreferredName(memory.preferredName);

    // No Puter account, no coach. Saying so on the whole screen beats a chat
    // that accepts your message and times out forty seconds later.
    return StreamBuilder<bool>(
      stream: PuterService.instance.authState,
      initialData: PuterService.instance.signedIn,
      builder: (context, auth) {
        if (auth.data != true) return const PuterGate();
        return _buildChat(context, c);
      },
    );
  }

  Widget _buildChat(BuildContext context, OmColors c) {
    final memory = context.watch<MemoryProvider>();
    return Consumer<CoachProvider>(
      builder: (context, coach, _) {
        // Auto-scroll whenever a new token arrives.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (coach.isStreaming) _scrollToEnd();
        });

        return Column(
          children: [
            // Messenger-style header: back to the previous tab, Mynd's avatar
            // with a live "active" dot, name + model picker, and the connect chip.
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  8, AppSpacing.screenTop, AppSpacing.screenH, 8),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 4),
                  Stack(
                    children: [
                      // The same living orb as the hero, small. One face for
                      // Mynd everywhere, not a mascot up here and a blob below.
                      //
                      // This plays. It used to be .still(), which skips the
                      // video and paints the gradient fallback, so the header
                      // showed a peach blob that read as a missing image rather
                      // than as Mynd. The avatar is the one place the face has
                      // to be recognisable, so it gets the decoder.
                      const FluidOrb(size: 42, glow: false),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: c.success,
                            shape: BoxShape.circle,
                            border: Border.all(color: c.bg, width: 2),
                          ),
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
                        Text('Mynd',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                    fontSize: 19, fontWeight: FontWeight.w800)),
                        const _ModelPicker(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // New chat. The history lives under the orb, so this is the
                  // only control needed up here.
                  OmTappable(
                    onTap: () {
                      Haptics.light();
                      context.read<CoachProvider>().startNewChat();
                    },
                    feedback: OmTapFeedback.none,
                    pressedScale: 0.86,
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                          color: c.surfaceAlt, shape: BoxShape.circle),
                      child: Icon(Icons.add_rounded, size: 20, color: c.text2),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
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
                      // The orb, then everything you have said to it before.
                      return Column(
                        children: [
                          const _CoachHero(),
                          _ThreadHistory(threads: coach.threads),
                        ],
                      );
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
            SafeArea(
              bottom: true,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  0,
                  AppSpacing.screenH,
                  8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Only show quick prompts if the user hasn't sent a message yet
                    // (messages.length <= 1 means only the welcome message is there).
                    if (coach.messages.length <= 1) ...[
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _prompts.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, i) => _PromptChip(
                            label: _prompts[i],
                            urgent: i == 0,
                            onTap: () => _send(_prompts[i]),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _CoachInput(
                        controller: _controller,
                        onSend: _send,
                        onVoice: _openVoice),
                  ],
                ),
              ),
            ), // Close SafeArea
          ],
        );
      },
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

/// Coach subtitle that doubles as the Puter model picker.
class _ModelPicker extends StatefulWidget {
  const _ModelPicker();
  @override
  State<_ModelPicker> createState() => _ModelPickerState();
}

class _ModelPickerState extends State<_ModelPicker> {
  /// A sheet, not a popup menu.
  ///
  /// The menu opened as a hard-edged rectangle pinned under a subtitle, in
  /// none of the app's own shapes, and every model in it was a bare line of
  /// text. Eight near-identical names need room to breathe and a tick you can
  /// find without reading all of them.
  Future<void> _choose() async {
    Haptics.light();
    final current = PuterService.instance.model;
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) {
        final c = sheet.omColors;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Text('which model',
                    style: Theme.of(sheet).textTheme.titleLarge),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text('they all sound a little different. try a few.',
                    style: Theme.of(sheet).textTheme.bodySmall),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  children: [
                    for (final m in kPuterModels)
                      OmTappable(
                        onTap: () => Navigator.of(sheet).pop(m.id),
                        feedback: OmTapFeedback.none,
                        pressedScale: 0.98,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: m.id == current ? c.primaryTint : c.surface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.label,
                                  style: Theme.of(sheet)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                        fontWeight: m.id == current
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                      ),
                                ),
                              ),
                              if (m.id == current)
                                Icon(OmIcons.byName('check'),
                                    size: 17, color: c.primary),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
    if (picked != null && mounted) {
      Haptics.select();
      setState(() => PuterService.instance.setModel(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final current = PuterService.instance.model;
    final label = kPuterModels
        .firstWhere((m) => m.id == current,
            orElse: () => (id: current, label: current))
        .label;
    return OmTappable(
      onTap: _choose,
      feedback: OmTapFeedback.none,
      pressedScale: 0.97,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text('$label · always here',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall),
          ),
          Icon(OmIcons.byName('chevR'), size: 13, color: c.text2),
        ],
      ),
    );
  }
}

/// Everything you have talked to Mynd about before, under the orb.
class _ThreadHistory extends StatelessWidget {
  const _ThreadHistory({required this.threads});

  final List<CoachThread> threads;

  @override
  Widget build(BuildContext context) {
    if (threads.isEmpty) return const SizedBox.shrink();
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text('earlier',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: c.text2,
                      fontWeight: FontWeight.w800,
                    )),
          ),
          for (final t in threads.take(12))
            OmTappable(
              onTap: () {
                Haptics.light();
                context.read<CoachProvider>().openThread(t.id);
              },
              feedback: OmTapFeedback.none,
              pressedScale: 0.98,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    const FluidOrb.still(size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(_ago(t.updatedAt),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: c.text2)),
                        ],
                      ),
                    ),
                    Icon(OmIcons.byName('chevR'), size: 15, color: c.text2),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _ago(DateTime at) {
    final d = DateTime.now().difference(at);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays == 1) return 'yesterday';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return DateFormat.MMMd().format(at);
  }
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

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 30),
      child: Column(
        children: [
          const FluidOrb(size: 132),
          const SizedBox(height: 28),
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

/// Thinking. The orb is the indicator - it is already alive, so it says
/// "someone is there" better than the words "Mynd is typing" ever did.
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 2),
      child: Row(
        children: [
          const FluidOrb.still(size: 26),
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

class _CoachInput extends StatelessWidget {
  const _CoachInput(
      {required this.controller, required this.onSend, required this.onVoice});

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onVoice;

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
            const SizedBox(width: 6),
            // Hands-free voice mode (Puter speech↔text + TTS).
            OmTappable(
              onTap: onVoice,
              feedback: OmTapFeedback.none,
              pressedScale: 0.88,
              child: SizedBox(
                width: 40,
                height: 42,
                child: Icon(OmIcons.byName('mic'), color: c.text2, size: 19),
              ),
            ),
            // The send key from the reference: a soft brand-tinted square with an
            // arrow, not a hard coral disc. It belongs to the same family as the
            // orb above it, which is the point.
            OmTappable(
              onTap: () => onSend(controller.text),
              feedback: OmTapFeedback.none,
              pressedScale: 0.88,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(15),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color.lerp(c.primary, Colors.white, 0.62)!,
                      Color.lerp(c.primary, c.accent, 0.30)!,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: c.primary.withValues(alpha: 0.30),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.arrow_upward_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
