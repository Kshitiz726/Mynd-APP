import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/routes/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../providers/motivation_provider.dart';
import '../../../widgets/om_glass.dart';
import '../../../widgets/om_tappable.dart';

/// Today's line, on the way past.
///
/// The same words that arrive as a notification, kept somewhere they can be
/// read again. A notification is gone the moment it is swiped, and the line
/// somebody wanted was usually the one that arrived while they were busy.
class MotivationCard extends StatefulWidget {
  const MotivationCard({super.key});

  @override
  State<MotivationCard> createState() => _MotivationCardState();
}

class _MotivationCardState extends State<MotivationCard> {
  @override
  void initState() {
    super.initState();
    // After the first frame, because refresh can reach for a location and the
    // OS prompt would otherwise land on a half-built screen.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final p = context.read<MotivationProvider>();
      await p.load();
      if (mounted) await p.refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final m = context.watch<MotivationProvider>();
    final line = m.latest;
    final setUp = m.settings.onboarded;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: OmTappable(
        onTap: () {
          Haptics.light();
          Navigator.of(context).pushNamed(AppRoutes.motivation);
        },
        feedback: OmTapFeedback.none,
        pressedScale: 0.99,
        child: OmGlass(
          borderRadius: 24,
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.sparkles, size: 17, color: c.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      setUp && line != null
                          ? (line.place == null
                              ? 'today'
                              : 'today, in ${line.place}')
                          : 'daily motivation',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                        color: c.text2,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      line?.text ??
                          (setUp
                              ? 'writing today\'s lines…'
                              : 'a few words a day, for where you are and what you are working on'),
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: line == null ? c.text2 : c.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(LucideIcons.chevronRight, size: 17, color: c.text2),
            ],
          ),
        ),
      ),
    );
  }
}
