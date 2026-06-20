import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/services/puter_service.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/chat_message.dart';
import '../../providers/coach_provider.dart';
import '../../providers/nav_provider.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_mascot.dart';
import '../../widgets/om_tappable.dart';
import 'coach_voice_screen.dart';
import 'puter_connect_screen.dart';

/// "coach" — Mynd, the pocket coach. A calm chat with one-tap prompts for the
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
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CoachVoiceScreen()));
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
              padding: const EdgeInsets.fromLTRB(8, AppSpacing.screenTop, AppSpacing.screenH, 8),
              child: Row(
                children: [
                  OmBackButton(onTap: () => context.read<NavProvider>().back()),
                  const SizedBox(width: 4),
                  Stack(
                    children: [
                      const OmMascot(size: 42),
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
                                ?.copyWith(fontSize: 19, fontWeight: FontWeight.w800)),
                        const _ModelPicker(),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const _ConnectPuterButton(),
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
                itemCount: coach.messages.length +
                    (coach.isLoading && !coach.isStreaming ? 1 : 0),
                itemBuilder: (context, i) {
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
                  _CoachInput(controller: _controller, onSend: _send, onVoice: _openVoice),
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
  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final current = PuterService.instance.model;
    final label = kPuterModels
        .firstWhere((m) => m.id == current, orElse: () => (id: current, label: current))
        .label;
    return PopupMenuButton<String>(
      tooltip: 'Choose AI model',
      position: PopupMenuPosition.under,
      onSelected: (id) {
        Haptics.select();
        setState(() => PuterService.instance.setModel(id));
      },
      itemBuilder: (_) => [
        for (final m in kPuterModels)
          PopupMenuItem(
            value: m.id,
            child: Row(
              children: [
                Icon(OmIcons.byName('check'),
                    size: 16, color: m.id == current ? c.primary : Colors.transparent),
                const SizedBox(width: 8),
                Text(m.label),
              ],
            ),
          ),
      ],
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

/// Appears until the user connects their Puter account (needed for the AI).
class _ConnectPuterButton extends StatelessWidget {
  const _ConnectPuterButton();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return StreamBuilder<bool>(
      stream: PuterService.instance.authState,
      initialData: PuterService.instance.signedIn,
      builder: (context, snap) {
        if (snap.data == true) return const SizedBox.shrink();
        return OmTappable(
          onTap: () {
            Haptics.medium();
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PuterConnectScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(gradient: c.brandGradient, borderRadius: BorderRadius.circular(AppRadius.pill)),
            child: const Text('Connect Puter',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        );
      },
    );
  }
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final mine = message.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        padding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: BoxDecoration(
          color: mine ? c.primary : c.surfaceAlt,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(mine ? 18 : 6),
            bottomRight: Radius.circular(mine ? 6 : 18),
          ),
        ),
        child: Text(
          message.text.isEmpty && message.isStreaming ? '…' : message.text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: mine ? Colors.white : c.text,
                fontWeight: mine ? FontWeight.w500 : FontWeight.w400,
              ),
        ),
      ),
    );
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 4),
      child: Text(
        'Mynd is typing…',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: c.text2, fontStyle: FontStyle.italic),
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
          color: urgent
              ? c.attention.withValues(alpha: 0.14)
              : c.surface,
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
  const _CoachInput({required this.controller, required this.onSend, required this.onVoice});

  final TextEditingController controller;
  final ValueChanged<String> onSend;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: onSend,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: c.text, fontSize: 15),
              decoration: InputDecoration(
                hintText: "tell Mynd what's going on…",
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
          GestureDetector(
            onTap: onVoice,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(OmIcons.byName('mic'), color: c.primary, size: 19),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => onSend(controller.text),
            child: Container(
              width: 42,
              height: 42,
              decoration:
                  BoxDecoration(color: c.accent, shape: BoxShape.circle),
              alignment: Alignment.center,
              child:
                  Icon(OmIcons.byName('send'), color: Colors.white, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
