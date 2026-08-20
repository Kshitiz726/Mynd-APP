import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/community/chat_models.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import 'group_members_sheet.dart';
import 'user_profile_sheet.dart';

/// A single conversation - group chat or 1:1 DM. Realtime text + media via
/// [ChatProvider]: optimistic sends, live typing indicators, instant history.
class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.title,
    this.iconName,
    this.iconColor,
    this.isGroup = false,
  });

  final String conversationId;
  final String title;
  final String? iconName;
  final String? iconColor;
  final bool isGroup;

  /// Open a conversation as a full-screen route (the reliable pattern on
  /// Windows - an in-tab overlay nested under the IndexedStack + the always-on
  /// Puter WebView could freeze input). Wires the provider, then pushes.
  static void open(
    BuildContext context, {
    required String id,
    required String title,
    String? iconName,
    String? iconColor,
    bool isGroup = false,
  }) {
    context.read<ChatProvider>().openChat(
          id: id,
          title: title,
          iconName: iconName,
          iconColor: iconColor,
          isGroup: isGroup,
        );
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: id,
          title: title,
          iconName: iconName,
          iconColor: iconColor,
          isGroup: isGroup,
        ),
      ),
    );
  }

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final ChatProvider _chat;
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  int _lastMsgCount = 0;

  @override
  void initState() {
    super.initState();
    _chat = context.read<ChatProvider>();
  }

  @override
  void dispose() {
    // exitConversation() notifies, and AppShell watches ChatProvider - notifying
    // here would rebuild the shell while this route is still deactivating, which
    // strands the inherited-widget dependents below it. Defer past the frame.
    // Guard on the id: the user may already have opened another conversation by
    // the time this runs, and clearing that one would empty a live chat.
    final chat = _chat;
    final id = widget.conversationId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (chat.activeConversationId == id) chat.exitConversation();
    });
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    Haptics.light();
    _chat.sendText(text);
    _controller.clear();
    _jumpToBottomSoon();
  }

  void _jumpToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  Color _hex(String? s, Color fallback) {
    if (s == null) return fallback;
    var h = s.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final chat = context.watch<ChatProvider>();
    final msgs = chat.messages;
    // Only auto-scroll when the message count actually changes - calling
    // animateTo on every rebuild (incl. typing pings) caused jank/freezes.
    if (msgs.length != _lastMsgCount) {
      _lastMsgCount = msgs.length;
      _jumpToBottomSoon();
    }

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 56,
        // Pop the route; dispose() calls exitConversation() to unsubscribe.
        leading: OmBackButton(onTap: () => Navigator.of(context).maybePop()),
        title: GestureDetector(
          onTap: widget.isGroup
              ? () => GroupMembersSheet.show(context, widget.conversationId, widget.title)
              : null,
          behavior: HitTestBehavior.opaque,
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _hex(widget.iconColor, c.primary).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: Icon(OmIcons.byName(widget.iconName ?? (widget.isGroup ? 'users' : 'user')),
                    size: 18, color: _hex(widget.iconColor, c.primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium),
                    if (widget.isGroup)
                      Text('tap to see members',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (widget.isGroup)
            OmTappable(
              onTap: () => GroupMembersSheet.show(context, widget.conversationId, widget.title),
              pressedScale: 0.9,
              child: Padding(
                padding: const EdgeInsets.only(right: 14, left: 6),
                child: Icon(OmIcons.byName('users'), color: c.text, size: 22),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: msgs.isEmpty
                  ? _EmptyChat(title: widget.title, isGroup: widget.isGroup)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
                      itemCount: msgs.length,
                      itemBuilder: (context, i) {
                        final m = msgs[i];
                        final prev = i > 0 ? msgs[i - 1] : null;
                        final next = i < msgs.length - 1 ? msgs[i + 1] : null;
                        // A new speaker, or a gap of more than five minutes,
                        // starts a fresh group. Consecutive lines from one
                        // person then read as one turn, the way they were typed.
                        final startsGroup = prev == null ||
                            prev.senderId != m.senderId ||
                            m.createdAt.difference(prev.createdAt).inMinutes >= 5;
                        final endsGroup = next == null ||
                            next.senderId != m.senderId ||
                            next.createdAt.difference(m.createdAt).inMinutes >= 5;
                        final showSender = widget.isGroup && !m.mine && startsGroup;
                        // One divider per day, not one per hour.
                        final showTimeHeader =
                            prev == null || !_sameDay(prev.createdAt, m.createdAt);
                        return GestureDetector(
                          onLongPress: () {
                            Haptics.light();
                            _chat.setReplyingTo(m);
                          },
                          child: _Bubble(
                            msg: m,
                            showSender: showSender,
                            startsGroup: startsGroup,
                            endsGroup: endsGroup,
                            onReply: () => _chat.setReplyingTo(m),
                            showTimeHeader: showTimeHeader,
                            senderColor: _hex(m.senderColor, c.primary),
                            onRetry: () => _chat.retry(m),
                            onTapSender: widget.isGroup && !m.mine
                                ? () => UserProfileSheet.show(context, m.senderId, fallbackName: m.senderName)
                                : null,
                          ),
                        );
                      },
                    ),
            ),
            _TypingIndicator(label: chat.typingLabel),
            _Composer(
              controller: _controller,
              onSend: _send,
              onChanged: _chat.onComposerChanged,
              replyingTo: chat.replyingTo,
              onCancelReply: () => chat.setReplyingTo(null),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator({required this.label});
  final String? label;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      child: label == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Row(
                children: [
                  Text(label!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: c.text2,
                            fontStyle: FontStyle.italic,
                          )),
                ],
              ),
            ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.msg,
    required this.showSender,
    required this.showTimeHeader,
    required this.senderColor,
    required this.onRetry,
    required this.onReply,
    this.startsGroup = true,
    this.endsGroup = true,
    this.onTapSender,
  });

  final ChatMsg msg;
  final bool showSender;
  final bool showTimeHeader;
  final Color senderColor;
  final VoidCallback onRetry;
  final VoidCallback onReply;

  /// First and last of a run from the same person. Only the last one gets a
  /// tail and a timestamp, so a burst of messages reads as one block.
  final bool startsGroup;
  final bool endsGroup;

  final VoidCallback? onTapSender;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final mine = msg.mine;
    return Padding(
      padding: EdgeInsets.only(top: startsGroup ? 10 : 2, bottom: 1),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (showTimeHeader)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.surfaceAlt,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _dayLabel(msg.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: c.text2,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
            ),
          // Swipe to reply, the gesture everyone already has in their hands.
          // The swipe used to reveal a timestamp, and replying was hidden
          // behind a long-press that nobody finds.
          Dismissible(
            key: ValueKey(msg.id),
            direction: mine ? DismissDirection.endToStart : DismissDirection.startToEnd,
            confirmDismiss: (_) async {
              Haptics.light();
              onReply();
              return false; // snap back; the composer takes it from here
            },
            dismissThresholds: const {
              DismissDirection.endToStart: 0.22,
              DismissDirection.startToEnd: 0.22,
            },
            background: Container(
              alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Icon(OmIcons.byName('cornerUpLeft'), size: 18, color: c.primary),
            ),
            child: Row(
              mainAxisAlignment: mine ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!mine && showSender) ...[
                  OmTappable(
                    onTap: onTapSender,
                    child: OmAvatar(
                      userId: msg.senderId,
                      fallbackInitial: msg.senderInitial,
                      fallbackColor: senderColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else if (!mine) ...[
                  const SizedBox(width: 36),
                ],
                Column(
                  crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  children: [
                    if (showSender)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 3),
                        child: OmTappable(
                          onTap: onTapSender,
                          child: Text(msg.senderName,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: senderColor, letterSpacing: 0.1)),
                        ),
                      ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.70),
                      child: _content(context, mine, c),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (mine && msg.status == SendStatus.failed)
            Padding(
              padding: const EdgeInsets.only(top: 3, right: 4),
              child: OmTappable(
                onTap: onRetry,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(OmIcons.byName('refresh'), size: 12, color: c.error),
                    const SizedBox(width: 3),
                    Text('Failed - tap to retry',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.error)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, bool mine, OmColors c) {
    // The tail is drawn only on the last bubble of a run, so a burst of
    // messages reads as one block rather than a stack of separate cards.
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(mine || !endsGroup ? 18 : 5),
      bottomRight: Radius.circular(!mine || !endsGroup ? 18 : 5),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: mine ? c.brandGradient : null,
        color: mine ? null : c.surface,
        borderRadius: radius,
        border: mine ? null : Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (msg.replyToBody != null)
            Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.only(left: 8),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: mine ? Colors.white54 : c.primary, width: 3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg.replyToSender ?? 'Someone',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: mine ? Colors.white70 : c.primary,
                            fontWeight: FontWeight.w600,
                          )),
                  const SizedBox(height: 2),
                  Text(msg.replyToBody!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: mine ? Colors.white70 : c.text2,
                          )),
                ],
              ),
            ),
          Text(
            msg.body,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: mine ? Colors.white : c.text,
                  height: 1.35,
                ),
          ),
          // The time and the delivery state ride inside the last bubble of a
          // run. "Did that actually send?" is a question a chat has to answer
          // without being asked.
          if (endsGroup) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  DateFormat.jm().format(msg.createdAt).toLowerCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 10,
                        color: mine ? Colors.white70 : c.text2,
                      ),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  _StatusTick(status: msg.status),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Sending, sent, failed. Three states, three glyphs, no words.
class _StatusTick extends StatelessWidget {
  const _StatusTick({required this.status});

  final SendStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      SendStatus.sending => SizedBox(
          width: 9,
          height: 9,
          child: CircularProgressIndicator(
            strokeWidth: 1.4,
            color: Colors.white.withValues(alpha: 0.75),
          ),
        ),
      SendStatus.failed =>
        const Icon(Icons.error_outline_rounded, size: 12, color: Colors.white),
      _ => Icon(Icons.done_rounded, size: 12, color: Colors.white.withValues(alpha: 0.85)),
    };
  }
}

/// Nothing said yet. Better than a bare "Say hello": it names who you are about
/// to talk to, so the screen does not read as a dead end.
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.title, required this.isGroup});

  final String title;
  final bool isGroup;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
              child: Icon(OmIcons.byName(isGroup ? 'users' : 'message'),
                  size: 26, color: c.primary),
            ),
            const SizedBox(height: 16),
            Text(
              isGroup ? 'no one has said anything yet' : 'this is the start with $title',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'say whatever. low bar here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2),
            ),
          ],
        ),
      ),
    );
  }
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// "Today" / "Yesterday" / a weekday / a date. Nobody needs the year on a chat
/// they had on Tuesday.
String _dayLabel(DateTime t) {
  final now = DateTime.now();
  if (_sameDay(t, now)) return 'Today';
  if (_sameDay(t, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  if (now.difference(t).inDays < 7) return DateFormat.EEEE().format(t);
  return DateFormat.yMMMd().format(t);
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onChanged,
    this.replyingTo,
    this.onCancelReply,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final ChatMsg? replyingTo;
  final VoidCallback? onCancelReply;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (replyingTo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
              child: Row(
                children: [
                  Icon(OmIcons.byName('cornerUpLeft'), size: 16, color: c.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Replying to ${replyingTo!.senderName}',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.primary)),
                        Text(replyingTo!.body,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2)),
                      ],
                    ),
                  ),
                  OmTappable(
                    onTap: onCancelReply,
                    child: Icon(Icons.close, size: 18, color: c.text2),
                  ),
                ],
              ),
            ),
          Row(
            children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.surfaceAlt,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: c.border),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                onChanged: onChanged,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                decoration: const InputDecoration(
                  hintText: 'Message…',
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          OmTappable(
            onTap: onSend,
            pressedScale: 0.9,
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(gradient: c.brandGradient, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 22),
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }
}
