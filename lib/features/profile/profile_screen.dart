import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/constants/legal.dart';
import '../../core/config/store_policy.dart';
import '../../core/routes/app_routes.dart';
import '../../core/services/api_client.dart';
import '../../core/services/google_auth.dart';
import '../../core/services/coach_memory_service.dart';
import '../../core/services/realtime_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';

import '../../core/utils/toast.dart';
import '../../providers/nav_provider.dart';
import '../../providers/health_consent_provider.dart';
import '../../providers/premium_provider.dart';
import '../../providers/settings_provider.dart';
import '../../widgets/om_switch.dart';
import '../../widgets/om_tappable.dart';
import '../coach/agent_picker_screen.dart';
import '../memory/memory_screen.dart';
import '../soul/soul_screen.dart';
import 'about_screen.dart';
import 'connections_screen.dart';
import 'account_data_screen.dart';
import 'blocked_accounts_screen.dart';
import 'health_data_screen.dart';
import 'profile_identity.dart';

/// Settings.
///
/// Rebuilt on the reference: a portrait and a name at the top, a plan card, and
/// after that nothing but quiet grouped rows with chevrons.
///
/// The previous version had five sections, eighteen rows, and every icon in a
/// different colour, which turned a settings page into a fairground. Most of it
/// was not settings either: "write a review", "redeem a code", "auto low-stim
/// on brain-dead". Those are gone.
///
/// What stayed had to earn it. The sensory toggles are not decoration in an
/// ADHD app, they are the accessibility layer, so low-stim, dark mode,
/// hyperlegible type, haptics and reduced motion all remain. Memory is here
/// because this screen is its only entrance; deleting the row would delete the
/// feature. Notes went the other way: it was
/// a second, worse place to write things down next to the coach and the
/// backlog, so it is gone rather than kept out of politeness.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  /// Confirm, then fully tear down the session: clear the saved token, drop the
  /// realtime socket, wipe this device's coach memory (so the next account on
  /// the same device starts clean), and return to the login screen.
  Future<void> _confirmSignOut(BuildContext context) async {
    Haptics.medium();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
            "You'll need to continue with Google again to come back in."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                Text('Sign out', style: TextStyle(color: ctx.omColors.error)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;

    await ApiClient.instance.signOut();
    // Drop the Google grant as well, or the next launch signs straight back in.
    await GoogleAuth.forget();
    RealtimeService.instance.dispose();
    await CoachMemoryService.instance.clearAll();

    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true)
        .pushNamedAndRemoveUntil(AppRoutes.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final premium = context.watch<PremiumProvider>().isPremium;
    final c = context.omColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.screenH, 4,
              AppSpacing.screenH, AppSpacing.screenBottom),
          children: [
            // ── Header: back, title, nothing else ──
            Row(
              children: [
                _CircleButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () {
                    if (Navigator.of(context).canPop()) {
                      Navigator.of(context).pop();
                    } else {
                      context.read<NavProvider>().select(AppTab.coach);
                    }
                  },
                ),
                Expanded(
                  child: Text(
                    'Settings',
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 19),
                  ),
                ),
                // Balances the back button so the title sits truly centred.
                const SizedBox(width: 40),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            // ── Who you are ──
            // Both the picture and the name are yours to change here; see
            // ProfileIdentity.
            ProfileIdentity(
              trailing: premium
                  ? _MemberTag(tier: context.watch<PremiumProvider>().tier)
                  : null,
            ),
            const SizedBox(height: AppSpacing.xl),

            // ── The plan ──
            // The plan card is shown to everyone, so its tap is one of only two
            // routes to the paywall that an isPremium check does not already
            // close. On a build that may not sell, it stops being a door.
            _PlanCard(
              premium: premium,
              tier: context.watch<PremiumProvider>().tier,
              onTap: StorePolicy.canSell
                  ? () => Navigator.of(context).pushNamed(AppRoutes.paywall)
                  : null,
            ),
            const SizedBox(height: AppSpacing.xl),

            const _GroupLabel('Account'),
            _Group(children: [
              // Opens the account screen, which is where "delete my account"
              // lives. It used to open the PAYWALL - so the delete path had no
              // caller anywhere in the app and AccountDataScreen was orphaned
              // code. Apple requires account deletion to be reachable from
              // inside the app (5.1.1(v)), so that was a rejection on its own,
              // quite apart from being a door to the paywall.
              // Labelled for both of the things behind it. There used to be a
              // second row, "Your data", down in the Privacy group, opening
              // this exact same screen - one destination wearing two names in
              // two places, which is a choice to make with no difference to
              // find at the end of it. One row, both words people search for.
              _Row(
                icon: Icons.person_outline_rounded,
                label: 'Account and your data',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AccountDataScreen(),
                  ),
                ),
              ),
              _Row(
                icon: Icons.notifications_none_rounded,
                label: 'Reminders',
                onTap: () =>
                    Navigator.of(context).pushNamed(AppRoutes.reminders),
              ),
              // Calendar and Gmail, together. The calendar switch used to live
              // at the top of the Schedule tab, which meant "what has access to
              // what" was answered in two different places, and the one people
              // go looking for when they have second thoughts is this one.
              _Row(
                icon: Icons.hub_outlined,
                label: 'Connections',
                onTap: () => ConnectionsScreen.open(context),
              ),
              _Row(
                icon: Icons.face_retouching_natural_outlined,
                label: 'Your coach',
                onTap: () => AgentPickerScreen.open(context),
              ),
              // Next to memory, because they are the pair: one is what it
              // knows about you, the other is how it talks to you. The second
              // steered every conversation while existing nowhere you could
              // go and look at it.
              _Row(
                icon: Icons.favorite_outline_rounded,
                label: 'Soul',
                onTap: () => SoulScreen.open(context),
              ),
              _Row(
                icon: Icons.psychology_outlined,
                label: 'Memory',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MemoryScreen()),
                ),
              ),
              // The two remaining things Guideline 1.2 asks for, next to each
              // other because they are the same conversation: somewhere to undo
              // a block, and somewhere to reach a person about one.
              _Row(
                icon: Icons.block_rounded,
                label: 'Blocked accounts',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => const BlockedAccountsScreen()),
                ),
              ),
              _Row(
                icon: Icons.mail_outline_rounded,
                label: 'Contact support',
                onTap: () => Legal.contactSupport(context),
                last: true,
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),

            // ── The accessibility layer. Not decoration in an app for ADHD. ──
            const _GroupLabel('How it feels'),
            _Group(children: [
              _ToggleRow(
                icon: Icons.blur_on_rounded,
                label: 'Low stimulation',
                value: settings.lowStim,
                onChanged: (_) => settings.toggleLowStim(),
              ),
              // Dark mode is a Premium perk. Free users see it locked: the
              // switch never moves, and tapping the row explains why and opens
              // the paywall. Premium users get the real toggle.
              _ToggleRow(
                icon: Icons.dark_mode_outlined,
                label: 'Dark mode',
                value: premium && settings.darkMode,
                locked: !premium,
                onChanged: premium ? (_) => settings.toggleDarkMode() : null,
                onLockedTap: () {
                  Haptics.light();
                  Toast.show(context, 'Dark mode is a Premium feature');
                  // See the plan card above: the route is not registered on a
                  // build that cannot sell, and pushing it anyway stacks a
                  // second app rather than opening a paywall.
                  if (StorePolicy.canSell) {
                    Navigator.of(context).pushNamed(AppRoutes.paywall);
                  }
                },
              ),
              _ToggleRow(
                icon: Icons.text_fields_rounded,
                label: 'Hyperlegible font',
                value: settings.hyperlegible,
                onChanged: (_) => settings.toggleHyperlegible(),
              ),
              _ToggleRow(
                icon: Icons.vibration_rounded,
                label: 'Haptics',
                value: settings.haptics,
                onChanged: (_) => settings.toggleHaptics(),
              ),
              _ToggleRow(
                icon: Icons.graphic_eq_rounded,
                label: 'Typing sound',
                value: settings.typingSound,
                onChanged: (_) => settings.toggleTypingSound(),
              ),
              _ToggleRow(
                icon: Icons.motion_photos_off_outlined,
                label: 'Reduce motion',
                value: settings.reduceMotion,
                onChanged: (_) => settings.toggleReduceMotion(),
                last: true,
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),

            // Its own group rather than a row inside "Account". The privacy
            // policy says this consent is asked for separately and can be
            // withdrawn here, and burying it between the plan and the logout
            // button would be technically true and practically not findable.
            const _GroupLabel('Privacy'),
            _Group(children: [
              _ConsentRow(
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const HealthDataScreen()),
                ),
              ),
              _Row(
                icon: Icons.policy_outlined,
                label: 'Privacy policy',
                onTap: () => Legal.openPrivacy(context),
              ),
              _Row(
                icon: Icons.gavel_rounded,
                label: 'Terms',
                onTap: () => Legal.openTerms(context),
                last: true,
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),

            const _GroupLabel('Settings'),
            _Group(children: [
              // Named after what is actually behind it. It said "Help &
              // Support" and opened a page of version numbers and licences,
              // while the row that does reach a human is "Contact support" in
              // the Account group - so the promising label was the wrong door
              // and the working one looked like the lesser of the two.
              _Row(
                icon: Icons.info_outline_rounded,
                label: 'About OurMynd',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                ),
              ),
              _Row(
                icon: Icons.logout_rounded,
                label: 'Logout',
                danger: true,
                onTap: () => _confirmSignOut(context),
                last: true,
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// The plain circular control in the header corner.
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.88,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: c.surface, shape: BoxShape.circle),
        child: Icon(icon, size: 24, color: c.text),
      ),
    );
  }
}

/// The plan banner. Colourful in every state, and it tells the truth about
/// which plan you are on: a warm invitation gradient when you are free, the
/// tier's own gradient (teal for Plus, violet-gold for Pro) once you subscribe.
/// A small gradient pill under the user's name once they subscribe - the
/// "member" badge. Colours match the tier's own gradient on the paywall.
class _MemberTag extends StatelessWidget {
  const _MemberTag({required this.tier});

  final String tier; // plus | pro

  @override
  Widget build(BuildContext context) {
    final isPro = tier == 'pro';
    final colors = isPro
        ? const [Color(0xFF6D3BF0), Color(0xFFF0B24A)]
        : const [Color(0xFF1FA2A6), Color(0xFF3E7BF0)];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: colors.first.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.workspace_premium_rounded,
              color: Colors.white, size: 14),
          const SizedBox(width: 5),
          Text(
            isPro ? 'PRO MEMBER' : 'PLUS MEMBER',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.premium,
    required this.tier,
    required this.onTap,
  });

  final bool premium;
  final String tier; // free | plus | pro

  /// Null on a build that may not sell, which makes the card inert rather than
  /// a route to a paywall nobody on that platform could complete.
  final VoidCallback? onTap;

  /// The gradient for the current state. Free is intentionally not grey - a flat
  /// white card here read as "off"; the point is to look like something worth
  /// tapping.
  List<Color> _gradient() {
    if (!premium) return const [Color(0xFF7C6FF0), Color(0xFFF0A479)];
    if (tier == 'pro') return const [Color(0xFF6D3BF0), Color(0xFFF0B24A)];
    return const [Color(0xFF1FA2A6), Color(0xFF3E7BF0)]; // plus
  }

  @override
  Widget build(BuildContext context) {
    final colors = _gradient();
    final title = !premium
        ? 'Free plan'
        : tier == 'pro'
            ? 'OurMynd Pro'
            : 'OurMynd Plus';
    final subtitle = !premium
        ? 'See what Premium adds'
        : 'Enjoy your premium features';
    final icon = !premium
        ? Icons.auto_awesome_outlined
        : Icons.workspace_premium_rounded;

    final tap = onTap;
    return OmTappable(
      // Inert, not merely undecorated, when there is nowhere to send them.
      onTap: tap == null
          ? null
          : () {
              Haptics.medium();
              tap();
            },
      feedback: OmTapFeedback.none,
      pressedScale: tap == null ? 1.0 : 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: colors,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: colors.first.withValues(alpha: 0.34),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 21),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.9), size: 20),
          ],
        ),
      ),
    );
  }
}

/// The health-data consent row.
///
/// Carries its current state as a subtitle rather than being a plain label with
/// a chevron. "Health data ›" tells you nothing you would act on; whether it is
/// on, and since when, is the entire reason someone opens Settings looking for
/// it, and putting it here means the common case needs no tap at all.
class _ConsentRow extends StatelessWidget {
  const _ConsentRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final consent = context.watch<HealthConsentProvider>();
    final granted = consent.granted;
    final at = consent.decidedAt?.toLocal();

    final state = granted ? 'On' : (consent.needsDecision ? 'Not set' : 'Off');
    final since = at == null ? null : '${at.day}/${at.month}/${at.year}';

    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
        ),
        child: Row(
          children: [
            Icon(Icons.favorite_border_rounded, size: 20, color: c.text),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Health data',
                      style: Theme.of(context).textTheme.bodyLarge),
                  const SizedBox(height: 2),
                  Text(
                    since == null ? state : '$state · since $since',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: granted ? c.success : c.text2,
                        ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.text2),
          ],
        ),
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: context.omColors.text2,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// A rounded card holding a run of rows, hairline-separated.
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.border.withValues(alpha: 0.6)),
      ),
      child: Column(children: children),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.label,
    required this.onTap,
    this.last = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool last;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final tint = danger ? c.error : c.text;
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.99,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(
                  bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyLarge
                      ?.copyWith(color: tint)),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.text2),
          ],
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onChanged,
    this.last = false,
    this.locked = false,
    this.onLockedTap,
  });

  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool last;

  /// A premium-gated row: the switch is replaced by a "Premium" pill and the
  /// whole row taps through to [onLockedTap] instead of toggling.
  final bool locked;
  final VoidCallback? onLockedTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final row = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(
                bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: locked ? c.text2 : c.text),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: locked ? c.text2 : null),
            ),
          ),
          if (locked)
            const _PremiumPill()
          else
            OmSwitch(value: value, onChanged: onChanged ?? (_) {}),
        ],
      ),
    );

    if (!locked) return row;
    return OmTappable(
      onTap: onLockedTap ?? () {},
      feedback: OmTapFeedback.none,
      pressedScale: 0.99,
      child: row,
    );
  }
}

/// The small violet "Premium" chip shown where a locked feature's control would
/// be. A lock glyph plus the word, so the gate reads at a glance.
class _PremiumPill extends StatelessWidget {
  const _PremiumPill();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.primaryTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 12, color: c.primary),
          const SizedBox(width: 4),
          Text(
            'Premium',
            style: TextStyle(
              color: c.primary,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
