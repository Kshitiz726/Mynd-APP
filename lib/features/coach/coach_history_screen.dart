import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../providers/coach_provider.dart';
import '../../widgets/om_screen_header.dart';
import '../../widgets/om_tappable.dart';

/// Everything you have said to Mynd before, on its own screen.
///
/// It used to live under the orb as a full list, which meant the first thing a
/// new conversation showed you was every old one. A chat you had three weeks
/// ago is worth keeping and worth finding, but it is not worth reading on the
/// way in, so it moved behind one button and gained a search field.
///
/// Search reads the whole conversation, not just the title. You rarely remember
/// how a chat opened; you remember the one where you mentioned your sister, or
/// the deadline, and that word is usually somewhere in the middle.
class CoachHistoryScreen extends StatefulWidget {
  const CoachHistoryScreen({super.key});

  @override
  State<CoachHistoryScreen> createState() => _CoachHistoryScreenState();
}

class _CoachHistoryScreenState extends State<CoachHistoryScreen> {
  final _field = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final coach = context.watch<CoachProvider>();
    final q = _query.trim().toLowerCase();
    final threads = q.isEmpty
        ? coach.threads
        : coach.threads
            .where(
                (t) => t.messages.any((m) => m.text.toLowerCase().contains(q)))
            .toList();

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                  AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, 0),
              child: OmScreenHeader(
                title: 'earlier',
                subtitle: 'every conversation you have had with Mynd.',
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH, AppSpacing.lg, AppSpacing.screenH, 4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Icon(OmIcons.byName('search'), size: 17, color: c.text2),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _field,
                        onChanged: (v) => setState(() => _query = v),
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'search your chats',
                          hintStyle: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: c.text2),
                        ),
                      ),
                    ),
                    if (_query.isNotEmpty)
                      OmTappable(
                        onTap: () {
                          _field.clear();
                          setState(() => _query = '');
                        },
                        feedback: OmTapFeedback.none,
                        pressedScale: 0.86,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(OmIcons.byName('x'),
                              size: 16, color: c.text2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: threads.isEmpty
                  ? _Empty(searching: q.isNotEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
                          AppSpacing.md, AppSpacing.screenH, AppSpacing.xl),
                      itemCount: threads.length,
                      itemBuilder: (context, i) => _ThreadRow(
                        thread: threads[i],
                        query: q,
                        onOpen: () async {
                          Haptics.light();
                          await context
                              .read<CoachProvider>()
                              .openThread(threads[i].id);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        onDelete: () {
                          Haptics.light();
                          context
                              .read<CoachProvider>()
                              .deleteThread(threads[i].id);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadRow extends StatelessWidget {
  const _ThreadRow({
    required this.thread,
    required this.query,
    required this.onOpen,
    required this.onDelete,
  });

  final CoachThread thread;
  final String query;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  /// The line the search actually matched, so a result explains itself instead
  /// of showing a title that has nothing to do with what you typed.
  String _preview() {
    if (query.isNotEmpty) {
      for (final m in thread.messages) {
        final i = m.text.toLowerCase().indexOf(query);
        if (i == -1) continue;
        final from = (i - 24).clamp(0, m.text.length);
        final to = (i + 70).clamp(0, m.text.length);
        final snip = m.text.substring(from, to).replaceAll('\n', ' ').trim();
        return '${from > 0 ? '…' : ''}$snip${to < m.text.length ? '…' : ''}';
      }
    }
    return _ago(thread.updatedAt);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Dismissible(
      key: ValueKey(thread.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          decoration: BoxDecoration(
            color: c.error.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(OmIcons.byName('trash'), size: 18, color: c.error),
        ),
      ),
      child: OmTappable(
        onTap: onOpen,
        feedback: OmTapFeedback.none,
        pressedScale: 0.98,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration:
                    BoxDecoration(color: c.primaryTint, shape: BoxShape.circle),
                alignment: Alignment.center,
                child:
                    Icon(OmIcons.byName('history'), size: 16, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(thread.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(_preview(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

class _Empty extends StatelessWidget {
  const _Empty({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Text(
          searching
              ? 'nothing in your chats matches that.'
              : 'no earlier chats yet. this one counts as the first.',
          textAlign: TextAlign.center,
          style:
              Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2),
        ),
      ),
    );
  }
}
