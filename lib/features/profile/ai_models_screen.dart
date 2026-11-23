import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/ai/ai_connections.dart';
import '../../core/services/ai/chat_backend.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import 'widgets/ai_connect_sheet.dart';

/// Settings -> Model. Which provider writes the coach's replies.
///
/// Three options, one of which always works. The built-in provider needs no
/// account and is what everybody starts on; the other two run on the user's
/// own Claude or Gemini account, which costs them their own quota and in
/// exchange gives noticeably better conversation.
///
/// Selecting is separate from connecting on purpose. Somebody can pick Claude
/// before they have a key, and the row then shows them what is missing instead
/// of refusing the tap. Until it is connected the coach keeps answering on the
/// built-in provider rather than breaking, which is the fallback [AiRouter]
/// exists for.
class AiModelsScreen extends StatelessWidget {
  const AiModelsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    final conn = context.watch<AiConnections>();

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, AppSpacing.screenH, 8),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 6),
                  Text('Model', style: t.titleLarge),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.screenH,
                    AppSpacing.md, AppSpacing.screenH, AppSpacing.xxl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Who writes the coach\'s replies. Connecting Puter '
                      'unlocks Claude and Gemini, billed to your own Puter '
                      'account rather than metered by us.',
                      style: t.bodyMedium?.copyWith(color: c.text2, height: 1.55),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    for (final p in AiProvider.values) ...[
                      _ProviderCard(
                        provider: p,
                        selected: conn.selected == p,
                        connected: conn.isConnected(p),
                        model: conn.modelFor(p),
                        onSelect: () async {
                          Haptics.light();
                          await conn.select(p);
                          // Picking an unconnected provider is not an error,
                          // but leaving them on a screen that now says "not
                          // connected" without offering the fix would be.
                          if (p.needsPuter && !conn.isConnected(p) && context.mounted) {
                            await AiConnectSheet.open(context, p);
                          }
                        },
                        onConnect: () => AiConnectSheet.open(context, p),
                        onDisconnect: () async {
                          final sure = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Disconnect Puter?'),
                              content: const Text(
                                'Your Puter session is cleared. The coach '
                                'goes back to the built in model, so it keeps '
                                'working.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Disconnect'),
                                ),
                              ],
                            ),
                          );
                          if (sure != true) return;
                          await conn.disconnect();
                          if (context.mounted) {
                            Toast.show(context, 'Puter disconnected.');
                          }
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(LucideIcons.info, size: 16, color: c.text2),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'This changes the conversation only. The rest of '
                              'the app (your feed, goals, mood and memory) keeps '
                              'using the built-in provider, so connecting an '
                              'account never spends your quota in the '
                              'background.',
                              style: t.bodySmall
                                  ?.copyWith(color: c.text2, height: 1.45),
                            ),
                          ),
                        ],
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

/// One provider, its state, and the single action that makes sense next.
class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.provider,
    required this.selected,
    required this.connected,
    required this.model,
    required this.onSelect,
    required this.onConnect,
    required this.onDisconnect,
  });

  final AiProvider provider;
  final bool selected;
  final bool connected;
  final String? model;
  final VoidCallback onSelect;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;
    final needsKey = provider.needsPuter && !connected;

    return OmTappable(
      onTap: onSelect,
      feedback: OmTapFeedback.none,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: selected ? c.primary : c.border.withValues(alpha: 0.6),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: selected ? c.primary : c.text2,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(provider.label,
                              style: t.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700)),
                          if (connected && provider.needsPuter) ...[
                            const SizedBox(width: 8),
                            Icon(LucideIcons.circleCheck,
                                size: 14, color: c.success),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        // The model, once we know it, is more useful than the
                        // marketing line: it is what actually answers.
                        connected && (model?.isNotEmpty ?? false) && provider.needsPuter
                            ? model!
                            : provider.subtitle,
                        style: t.bodySmall?.copyWith(color: c.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (provider.needsPuter) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: _MiniAction(
                      label: needsKey ? 'Connect' : 'Reconnect',
                      icon: LucideIcons.link,
                      onTap: onConnect,
                    ),
                  ),
                  if (connected) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _MiniAction(
                        label: 'Disconnect',
                        icon: LucideIcons.unlink,
                        danger: true,
                        onTap: onDisconnect,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.label,
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tint = danger ? c.error : c.primary;
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.98,
      child: Container(
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.surfaceAlt,
          borderRadius: BorderRadius.circular(AppRadius.control),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: tint),
            const SizedBox(width: 6),
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: tint, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
