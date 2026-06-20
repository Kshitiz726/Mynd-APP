import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/api_config.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/om_icons.dart';
import '../../../providers/settings_provider.dart';
import '../../../widgets/om_avatar.dart';
import '../../../widgets/om_tappable.dart';
import '../../../widgets/om_top_bar.dart';

/// Personalized greeting + date, with the user's generated avatar on the right
/// that opens Profile. The name is the random handle minted at account creation
/// (e.g. "MellowOtter47"), and the greeting flexes with the time of day.
class GreetingHeader extends StatelessWidget {
  const GreetingHeader({super.key, required this.onAvatarTap});

  final VoidCallback onAvatarTap;

  String get _date {
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    return '${days[now.weekday - 1]}, ${months[now.month - 1]} ${now.day}';
  }

  String get _timeGreeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'good morning';
    if (h < 17) return 'good afternoon';
    return 'good evening';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final name = ApiConfig.instance.displayName ?? 'friend';
    final userId = ApiConfig.instance.userId ?? name;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return OmTopBar(
      title: '$_timeGreeting, $name',
      subtitle: _date,
      actions: [
        OmTappable(
          onTap: onAvatarTap,
          pressedScale: 0.9,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.primary.withValues(alpha: 0.25),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: OmAvatar(
              userId: userId,
              fallbackInitial: initial,
              fallbackColor: c.primary,
              size: 44,
            ),
          ),
        ),
      ],
    );
  }
}

/// The banner shown when low-stimulation mode is active.
class LowStimBanner extends StatelessWidget {
  const LowStimBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    if (!settings.lowStim) return const SizedBox.shrink();
    final c = context.omColors;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.energyDead.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.control),
      ),
      child: Row(
        children: [
          Icon(OmIcons.byName('battery'), size: 18, color: c.energyDead),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text("low-stimulation mode — we've calmed things down.",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text)),
          ),
          TextButton(
            onPressed: () => settings.toggleLowStim(false),
            style: TextButton.styleFrom(
              backgroundColor: c.surface,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('turn off', style: Theme.of(context).textTheme.labelMedium),
          ),
        ],
      ),
    );
  }
}

