import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/pro_features.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/routes/app_routes.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../models/agent.dart';
import '../../providers/agent_provider.dart';
import '../../providers/coach_provider.dart';
import '../../providers/premium_provider.dart';
import '../../widgets/agent_avatar.dart';
import '../../widgets/om_back_button.dart';
import '../../widgets/om_tappable.dart';
import 'agent_settings_screen.dart';

/// Choosing who coaches you.
///
/// Written as introductions rather than as a list of options, because that is
/// what the choice actually is. Each card says who the agent is in its own
/// voice and - the part most pickers leave out - who it is *wrong* for. An
/// agent that claims to be right for everyone is a theme, and switching to it
/// would feel like nothing, which is the failure this screen exists to avoid.
class AgentPickerScreen extends StatelessWidget {
  const AgentPickerScreen({super.key});

  static Future<void> open(BuildContext context) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AgentPickerScreen()),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final agents = context.watch<AgentProvider>();
    final premium = context.watch<PremiumProvider>().isPremium;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  8, AppSpacing.md, AppSpacing.screenH, 0),
              child: Row(
                children: [
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Who coaches you',
                      style: Theme.of(context)
                          .textTheme
                          .headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH, AppSpacing.sm, AppSpacing.screenH, 0),
              child: Text(
                'They are not skins. Each one thinks differently, talks '
                'differently and pushes you differently. You can change your '
                'mind whenever you like.',
                style: TextStyle(color: c.text2, height: 1.45),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenH,
                  AppSpacing.xl,
                  AppSpacing.screenH,
                  AppSpacing.screenBottom,
                ),
                children: [
                  const _UsageCard(),
                  const SizedBox(height: AppSpacing.xl),
                  for (final a in Agent.all)
                    _AgentCard(
                      agent: a,
                      selected: a.id == agents.selectedId,
                      customised: agents.isCustomised(a),
                      // Locked rather than hidden. Somebody deciding whether
                      // to subscribe should be able to see what the other
                      // coaches are; a hidden feature sells nothing and reads
                      // as the app having only one.
                      locked:
                          !ProFeatures.agentAvailable(a.id, premium: premium),
                      onSelect: () {
                        if (!ProFeatures.agentAvailable(a.id,
                            premium: premium)) {
                          Haptics.light();
                          Navigator.of(context).pushNamed(AppRoutes.paywall);
                          return;
                        }
                        Haptics.success();
                        agents.select(a.id);
                      },
                      onConfigure: () => AgentSettingsScreen.open(context, a),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// This week's conversation budget, in the one place somebody goes to look at
/// how their coach is set up.
///
/// Only messages to the coach are counted. The Feed, the scheduling and the
/// rest of the app's own reasoning run unmetered, and the card says so - a
/// usage figure with no scope attached invites people to assume that using the
/// app at all is spending something.
class _UsageCard extends StatefulWidget {
  const _UsageCard();

  @override
  State<_UsageCard> createState() => _UsageCardState();
}

class _UsageCardState extends State<_UsageCard> {
  @override
  void initState() {
    super.initState();
    // Fresh whenever this screen opens: the figure is the whole point of the
    // card, and a stale one is worse than none.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<CoachProvider>().refreshQuota();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final coach = context.watch<CoachProvider>();
    final used = coach.usedThisWeek;
    final limit = coach.weeklyLimit;

    final uncapped = limit == null && used != null;
    final known = used != null;
    final fraction = (limit == null || limit == 0 || used == null)
        ? 0.0
        : (used / limit).clamp(0.0, 1.0);
    final left = coach.remainingToday;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('this week',
                  style: TextStyle(
                    color: c.text2,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  )),
              const Spacer(),
              if (coach.quotaResetsAt != null)
                Text('resets Monday',
                    style: TextStyle(color: c.text2, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            !known
                ? 'Counting…'
                : uncapped
                    ? '$used messages'
                    : '$used of $limit messages',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (known && !uncapped) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.pill),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 7,
                backgroundColor: c.primary.withValues(alpha: 0.14),
                valueColor: AlwaysStoppedAnimation(
                  fraction >= 0.8 ? c.attention : c.primary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              left == null
                  ? ''
                  : left <= 0
                      ? 'None left. They come back on Monday.'
                      : '$left left',
              style: TextStyle(
                  color: c.text2, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Only messages to your coach count. The feed, your schedule and '
            'everything else the app works out for you are unlimited.',
            style: TextStyle(color: c.text2, height: 1.45, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({
    required this.agent,
    required this.selected,
    required this.locked,
    required this.customised,
    required this.onSelect,
    required this.onConfigure,
  });

  final Agent agent;
  final bool selected;

  /// Shown, but not yours yet. See the note at the call site for why these are
  /// not simply hidden.
  final bool locked;
  final bool customised;
  final VoidCallback onSelect;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: OmTappable(
        onTap: onSelect,
        feedback: OmTapFeedback.none,
        pressedScale: 0.99,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              // The selected card is outlined in that agent's own colour, not
              // the app's: the accent is part of who they are.
              color: selected
                  ? agent.accent.withValues(alpha: 0.85)
                  : c.border.withValues(alpha: 0.7),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Opacity(
                      opacity: locked ? 0.45 : 1,
                      child: AgentAvatar(
                        agent: agent,
                        size: 62,
                        // Selected one is alive; the rest are still, so the eye
                        // goes to the current choice instead of to four things
                        // moving at once.
                        mood: selected ? AgentMood.idle : AgentMood.idle,
                        showRing: selected,
                      )),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(agent.name,
                                style: t.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800)),
                            const SizedBox(width: 8),
                            if (selected)
                              Icon(Icons.check_circle_rounded,
                                  size: 19, color: agent.accent),
                            // A word, not just a padlock glyph. "PRO" says
                            // what the thing costs; a padlock on its own only
                            // says no, and leaves somebody guessing whether
                            // it is a subscription or something they have to
                            // unlock by using the app.
                            if (locked)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: agent.accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(OmIcons.byName('lock'),
                                        size: 11, color: agent.accent),
                                    const SizedBox(width: 4),
                                    Text('PRO',
                                        style: TextStyle(
                                          color: agent.accent,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.5,
                                        )),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          agent.tagline,
                          style: TextStyle(
                              color: c.text2,
                              height: 1.35,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(agent.description,
                  style: t.bodyLarge?.copyWith(height: 1.5)),
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                decoration: BoxDecoration(
                  color: agent.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: Text(
                  agent.bestFor,
                  style: TextStyle(color: c.text, height: 1.45, fontSize: 13.5),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  if (customised)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.md),
                      child: Row(
                        children: [
                          Icon(OmIcons.byName('sliders'),
                              size: 14, color: c.text2),
                          const SizedBox(width: 5),
                          Text('tuned',
                              style: TextStyle(
                                  color: c.text2,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  const Spacer(),
                  OmTappable(
                    onTap: onConfigure,
                    feedback: OmTapFeedback.light,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.surfaceAlt,
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        selected ? 'Configure' : 'Configure ${agent.name}',
                        style: TextStyle(
                            color: c.text,
                            fontWeight: FontWeight.w700,
                            fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
