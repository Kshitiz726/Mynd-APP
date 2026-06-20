import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/om_icons.dart';
import '../../providers/alerts_provider.dart';
import '../../widgets/om_card.dart';
import '../../widgets/om_tappable.dart';
import '../../widgets/om_top_bar.dart';
import '../notifications/notifications_screen.dart'; // for relativeTime

/// A clean history list of all non-urgent app activity (reminders, mentions, etc.)
/// that doesn't belong in the primary 'Alerts' tab.
class ActivityHistoryScreen extends StatelessWidget {
  const ActivityHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final isDark = context.isDark;
    
    // Filter out post comments, which belong in the main Alerts screen.
    final history = context.watch<AlertsProvider>().allNotifications
        .where((n) => n.kind != 'post_comment')
        .toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0E14) : c.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH, AppSpacing.screenTop, AppSpacing.screenH, 0),
              child: OmTopBar(
                title: 'activity history',
                leading: OmTappable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.surfaceAlt,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(OmIcons.byName('chevL'), size: 18, color: c.text),
                  ),
                ),
              ),
            ),
            Expanded(
              child: history.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(OmIcons.byName('clock'), size: 32, color: c.text2.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text('No recent activity', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(
                          AppSpacing.screenH, AppSpacing.md, AppSpacing.screenH, AppSpacing.screenBottom),
                      itemCount: history.length,
                      itemBuilder: (context, i) {
                        final n = history[i];
                        final payload = n.payload;
                        final title = payload['title'] as String? ?? 'Activity Update';
                        final body = payload['body'] as String? ?? payload['preview'] as String? ?? '';
                        
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: OmCard(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: c.primaryTint,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(OmIcons.byName('bell'), size: 18, color: c.primary),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title, style: Theme.of(context).textTheme.titleSmall),
                                      if (body.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
                                      ],
                                      const SizedBox(height: 6),
                                      Text(relativeTime(n.createdAt),
                                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: c.text2)),
                                    ],
                                  ),
                                ),
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
