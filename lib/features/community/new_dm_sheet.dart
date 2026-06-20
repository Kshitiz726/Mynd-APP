import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/api_client.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../core/utils/toast.dart';
import '../../models/focus/body_double.dart';
import '../../providers/chat_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_tappable.dart';
import 'chat_screen.dart';

/// "New message" — pick a friend (someone whose follow request you accepted, in
/// either direction) and open a 1:1 DM with them. Searchable by name.
class NewDmSheet extends StatefulWidget {
  const NewDmSheet({super.key});

  static void show(BuildContext context) {
    final chat = context.read<ChatProvider>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ChangeNotifierProvider.value(
        value: chat,
        child: const NewDmSheet(),
      ),
    );
  }

  @override
  State<NewDmSheet> createState() => _NewDmSheetState();
}

class _NewDmSheetState extends State<NewDmSheet> {
  final _search = TextEditingController();
  List<BdFriend> _friends = [];
  bool _loading = true;
  String _query = '';
  String? _openingId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final all = await ApiClient.instance.fetchFriends();
      // Only confirmed friends (accepted) can be DM'd.
      _friends = all.where((f) => f.accepted).toList();
    } catch (_) {
      // server offline — leave empty, the UI shows the empty state
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Color _hex(String? s, Color fallback) {
    if (s == null) return fallback;
    var h = s.replaceFirst('#', '');
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? fallback : Color(v);
  }

  Future<void> _openDm(BdFriend f) async {
    if (_openingId != null) return;
    setState(() => _openingId = f.id);
    Haptics.select();
    final chat = context.read<ChatProvider>();
    try {
      final cid = await chat.openDirect(f.id);
      if (!mounted) return;
      // Stable context for pushing the chat route after this sheet is dismissed.
      final rootCtx = Navigator.of(context, rootNavigator: true).context;
      Navigator.of(context).pop(); // close the picker sheet
      ChatScreen.open(
        rootCtx,
        id: cid,
        title: f.name,
        iconName: 'user',
        iconColor: f.color,
        isGroup: false,
      );
    } catch (_) {
      if (mounted) {
        setState(() => _openingId = null);
        Toast.show(context, "Couldn't open chat — is the server running?");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? _friends
        : _friends.where((f) => f.name.toLowerCase().contains(q)).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('new message', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('start a DM with a friend',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 14),
            // Search field
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(OmIcons.byName('search'), size: 18, color: c.text2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 14),
                        hintText: 'Search friends',
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : shown.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 36),
                          child: Center(
                            child: Text(
                              _friends.isEmpty
                                  ? 'no friends yet — accept a follow request to add one'
                                  : 'no one matches "$_query"',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, i) {
                            final f = shown[i];
                            return OmTappable(
                              onTap: () => _openDm(f),
                              pressedScale: 0.98,
                              child: Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: c.surface,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    OmAvatar(
                                      userId: f.id,
                                      fallbackInitial: f.initial,
                                      fallbackColor: _hex(f.color, c.primary),
                                      size: 44,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(f.name,
                                          style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 15)),
                                    ),
                                    if (_openingId == f.id)
                                      const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    else
                                      Icon(OmIcons.byName('chevR'), size: 18, color: c.text2),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
