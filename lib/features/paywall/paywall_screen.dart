import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/services/billing_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../providers/premium_provider.dart';
import '../../widgets/om_tappable.dart';

/// The paywall: pick a tier (Plus or Pro) and an interval (monthly or yearly),
/// then subscribe through Stripe's hosted Checkout. We open the hosted page in
/// the browser; when the app returns to the foreground we reconcile the session
/// with the server, so premium unlocks the moment payment clears.
///
/// It takes its colours from the app, like every other screen - the offer
/// arrives in the same room as everything else, so the only thing that changes
/// is what is being said.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

/// Static copy for each tier. Prices come live from Stripe; this is only the
/// name and the "what you get" list.
class _TierInfo {
  const _TierInfo({
    required this.id,
    required this.name,
    required this.tagline,
    required this.benefits,
    required this.colors,
    this.badge,
  });
  final String id; // 'plus' | 'pro'
  final String name;
  final String tagline;
  final List<String> benefits;
  final List<Color> colors;
  final String? badge;
}

/// What each plan promises.
///
/// Every line here has to be something the app actually does, checked against
/// the code that enforces it, because this screen is the one place where a
/// vague claim becomes a charge on somebody's card. Two things are gated
/// today and only two: the daily message cap (coach_screen.dart,
/// kFreeCoachMessageLimit) and editing your memory by hand
/// (memory_screen.dart). Both lift at Plus. Nothing else in the app reads the
/// tier at all, so nothing else may be claimed here.
///
/// Pro therefore has no feature of its own to name yet. Rather than invent
/// one, it says what it honestly is. Anything added to this list needs a gate
/// behind it first.
const _tiers = [
  _TierInfo(
    id: 'plus',
    name: 'OurMynd Plus',
    tagline: 'Talk to Mynd as much as you need.',
    benefits: [
      'Unlimited messages with Mynd',
      'Edit your memory by hand',
      'Everything in the free plan',
      'Support a small, independent app',
    ],
    colors: [Color(0xFF1FA2A6), Color(0xFF3E7BF0)],
    badge: 'MOST POPULAR',
  ),
  _TierInfo(
    id: 'pro',
    name: 'OurMynd Pro',
    tagline: 'Back OurMynd at a higher tier.',
    benefits: [
      'Everything in Plus',
      'A bigger share towards building the app',
    ],
    colors: [Color(0xFF6D3BF0), Color(0xFFF0B24A)],
  ),
];

/// The free baseline, shown for comparison. Not purchasable.
///
/// Written from what the code enforces, not from what a free tier usually
/// looks like: there is no task cap and no habit cap anywhere in the app, so
/// the old "3 active tasks max" and "1 habit tracker" were describing limits
/// that do not exist and undersold the free plan to no purpose.
const _freeBenefits = [
  '5 messages a day with Mynd',
  'Unlimited tasks, habits and notes',
  'Focus sessions, rooms and ambience',
  'Your full planner and reminders',
  'Read your memory, but not edit it',
];

class _PaywallScreenState extends State<PaywallScreen>
    with WidgetsBindingObserver {
  String _interval = 'month'; // 'month' | 'year'
  String _tier = 'plus';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Load the catalogue and re-check where the user stands.
    final premium = context.read<PremiumProvider>();
    premium.loadPlans();
    premium.refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context.read<PremiumProvider>().clearPending();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the Stripe browser tab: reconcile checkout or a portal
    // change (cancel / switch plan).
    if (state == AppLifecycleState.resumed) {
      _reconcile();
      context.read<PremiumProvider>().reconcilePortalOnResume();
    }
  }

  Future<void> _reconcile() async {
    final premium = context.read<PremiumProvider>();
    if (!premium.awaitingReturn) return;
    final nowPremium = await premium.reconcileOnResume();
    if (nowPremium && mounted) {
      Haptics.success();
      Toast.show(context, "You're premium now — enjoy 🎉");
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _manageSubscription() async {
    final premium = context.read<PremiumProvider>();
    Haptics.medium();
    final ok = await premium.openBillingPortal();
    if (!ok && mounted) {
      Toast.show(context, "Couldn't open billing — try again");
    }
  }

  BillingPlan? _planFor(PremiumProvider premium, String tier, String interval) {
    for (final p in premium.plans) {
      if (p.tier == tier && p.interval == interval) return p;
    }
    return null;
  }

  Future<void> _subscribe() async {
    final premium = context.read<PremiumProvider>();
    final plan = _planFor(premium, _tier, _interval);
    if (plan == null) {
      Toast.show(context, 'That plan is unavailable right now');
      return;
    }
    Haptics.medium();
    final launched = await premium.startCheckout(plan.id);
    if (!launched && mounted) {
      Toast.show(context, "Couldn't open checkout — try again");
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final premium = context.watch<PremiumProvider>();

    return Scaffold(
      backgroundColor: c.bg,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [c.bg, c.primaryTint],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child:
                    _CloseButton(onTap: () => Navigator.of(context).maybePop()),
              ),
              Expanded(
                child: premium.isPremium
                    ? _AlreadyPremium(
                        tier: premium.tier,
                        busy: premium.busy,
                        onManage: _manageSubscription,
                      )
                    : _buildOffer(context, premium),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOffer(BuildContext context, PremiumProvider premium) {
    final c = context.omColors;
    final loading = premium.loadingPlans && premium.plans.isEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 4, 24, 20),
      children: [
        const SizedBox(height: 8),
        Text(
          'Choose your plan',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: c.text,
            fontSize: 30,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Unlock the full OurMynd. Cancel anytime.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text2, fontSize: 14, height: 1.45),
        ),
        const SizedBox(height: 22),

        // Monthly / Yearly.
        _IntervalToggle(
          value: _interval,
          onChanged: (v) {
            Haptics.select();
            setState(() => _interval = v);
          },
        ),
        const SizedBox(height: 18),

        if (loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          for (final t in _tiers)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _TierCard(
                info: t,
                plan: _planFor(premium, t.id, _interval),
                monthlyPlan: _planFor(premium, t.id, 'month'),
                selected: _tier == t.id,
                onTap: () {
                  Haptics.select();
                  setState(() => _tier = t.id);
                },
              ),
            ),
          const _FreeCard(),
          const SizedBox(height: 16),
          _CtaButton(
            label: premium.busy
                ? 'Opening checkout…'
                : 'Subscribe to ${_tier == 'pro' ? 'Pro' : 'Plus'}',
            busy: premium.busy,
            onTap: premium.busy ? null : _subscribe,
          ),
          const SizedBox(height: 10),
          if (premium.awaitingReturn)
            Center(
              child: OmTappable(
                onTap: _reconcile,
                feedback: OmTapFeedback.light,
                pressedScale: 0.97,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    "I've completed payment",
                    style: TextStyle(
                        color: c.primary,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          const _LegalRow(),
        ],
      ],
    );
  }
}

/// The Monthly / Yearly segmented control.
class _IntervalToggle extends StatelessWidget {
  const _IntervalToggle({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    Widget seg(String id, String label, {String? note}) {
      final active = value == id;
      return Expanded(
        child: OmTappable(
          onTap: () => onChanged(id),
          feedback: OmTapFeedback.none,
          pressedScale: 0.98,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: active ? c.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: active ? Colors.white : c.text2,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: active
                          ? Colors.white.withValues(alpha: 0.22)
                          : c.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      note,
                      style: TextStyle(
                        color: active ? Colors.white : c.primary,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          seg('month', 'Monthly'),
          seg('year', 'Yearly', note: 'SAVE'),
        ],
      ),
    );
  }
}

/// One selectable tier card, priced for the chosen interval.
class _TierCard extends StatelessWidget {
  const _TierCard({
    required this.info,
    required this.plan,
    required this.monthlyPlan,
    required this.selected,
    required this.onTap,
  });

  final _TierInfo info;
  final BillingPlan? plan;
  final BillingPlan? monthlyPlan; // to compute yearly savings
  final bool selected;
  final VoidCallback onTap;

  /// "Save 17%" when a yearly plan beats 12× the monthly one, else null.
  String? _savings() {
    final p = plan;
    if (p == null || p.interval != 'year' || p.amount == null) return null;
    final m = monthlyPlan?.amount;
    if (m == null || m == 0) return null;
    final full = m * 12;
    if (p.amount! >= full) return null;
    final pct = ((1 - p.amount! / full) * 100).round();
    return pct > 0 ? 'Save $pct%' : null;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final price = plan?.priceText ?? '';
    final suffix = plan?.intervalSuffix ?? '';
    final savings = _savings();

    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? c.primary : c.border,
            width: selected ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // Tier glyph in its own gradient.
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: info.colors,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    info.id == 'pro'
                        ? Icons.workspace_premium_rounded
                        : Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            info.name,
                            style: TextStyle(
                              color: c.text,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (info.badge != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: info.colors),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                info.badge!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        info.tagline,
                        style: TextStyle(color: c.text2, fontSize: 12.5),
                      ),
                    ],
                  ),
                ),
                // Selection tick.
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.circle_outlined,
                  color: selected ? c.primary : c.text2,
                  size: 24,
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Price line.
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  price.isEmpty ? '—' : price,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  suffix,
                  style: TextStyle(color: c.text2, fontSize: 14),
                ),
                if (savings != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.primary.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      savings,
                      style: TextStyle(
                        color: c.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 14),
            for (final b in info.benefits)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Icon(Icons.check_rounded, size: 18, color: c.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        b,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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

/// The free baseline, shown for comparison beneath the paid tiers. Flat, muted,
/// not selectable - it's what you already have, so the eye lands on the tiers
/// above it, not here.
class _FreeCard extends StatelessWidget {
  const _FreeCard();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Free',
                style: TextStyle(
                  color: c.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: c.text2.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'CURRENT PLAN',
                  style: TextStyle(
                    color: c.text2,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '£0',
                style: TextStyle(
                  color: c.text2,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final b in _freeBenefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.remove_rounded, size: 18, color: c.text2),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        color: c.text2,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Shown when the user already has a subscription: their tier, the features it
/// unlocks, and a way into Stripe's Billing Portal to switch plan or cancel.
class _AlreadyPremium extends StatelessWidget {
  const _AlreadyPremium({
    required this.tier,
    required this.busy,
    required this.onManage,
  });

  final String tier;
  final bool busy;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final isPro = tier == 'pro';
    final name = isPro ? 'OurMynd Pro' : 'OurMynd Plus';
    // Show the tier's own unlocked list (Pro shows Plus's list too, since Pro
    // "includes everything in Plus").
    final info = _tiers.firstWhere((t) => t.id == tier, orElse: () => _tiers[0]);
    final plusInfo = _tiers.firstWhere((t) => t.id == 'plus');
    // Pro includes Plus, so start from Plus and add Pro's extras, skipping the
    // "Everything in Plus" line and any benefit already listed (dedup).
    final features = <String>[...plusInfo.benefits];
    if (isPro) {
      for (final b in info.benefits) {
        if (b != 'Everything in Plus' && !features.contains(b)) features.add(b);
      }
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      children: [
        const SizedBox(height: 12),
        Center(
          child: Container(
            width: 72,
            height: 72,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: c.brandGradient,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.workspace_premium_rounded,
                color: Colors.white, size: 34),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          "You're on $name",
          textAlign: TextAlign.center,
          style: TextStyle(
              color: c.text, fontSize: 24, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          'Everything below is unlocked. Thank you for supporting OurMynd.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text2, fontSize: 14, height: 1.45),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "What's unlocked",
                style: TextStyle(
                    color: c.text, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              for (final f in features)
                Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 18, color: c.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          f,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _CtaButton(
          label: busy ? 'Opening…' : 'Manage subscription',
          busy: busy,
          onTap: busy ? null : onManage,
        ),
        const SizedBox(height: 10),
        Text(
          'Switch between Plus and Pro, update your card, or cancel anytime — '
          'all handled securely by Stripe.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text2, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onTap, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap ?? () {},
      feedback: OmTapFeedback.none,
      pressedScale: 0.97,
      child: Opacity(
        opacity: onTap == null ? 0.7 : 1,
        child: Container(
          height: 54,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: c.brandGradient,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: [
              BoxShadow(
                color: c.primary.withValues(alpha: 0.34),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: busy
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.4, color: Colors.white),
                )
              : Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
      ),
    );
  }
}

class _LegalRow extends StatelessWidget {
  const _LegalRow();

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: context.omColors.text2, fontSize: 11.5);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Restore Purchase', style: style),
        Text('Privacy Policy', style: style),
        Text('Terms of Use', style: style),
      ],
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.86,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Icon(
          Icons.close_rounded,
          size: 24,
          color: context.omColors.text2,
        ),
      ),
    );
  }
}
