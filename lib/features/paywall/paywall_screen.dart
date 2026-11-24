import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/config/pro_features.dart';
import '../../core/config/store_policy.dart';
import '../../core/constants/app_spacing.dart';
import '../../core/constants/legal.dart';
import '../../core/services/billing_service.dart';
import '../../core/services/iap_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../providers/premium_provider.dart';
import '../../widgets/om_tappable.dart';

/// The paywall: pick an interval (monthly or yearly), then subscribe on
/// whichever rail this platform uses.
///
/// On iOS that is StoreKit - Apple's payment sheet appears over this screen,
/// the transaction is verified by our server, and entitlement flips before the
/// sheet has finished dismissing. Everywhere else it is Stripe's hosted
/// Checkout in the system browser, reconciled when the app returns to the
/// foreground.
///
/// The screen itself does not branch on which: [PremiumProvider.plans] is the
/// same shape either way, and prices are always the store's own string rather
/// than one we format.
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
  });
  final String id; // 'plus' | 'pro'
  final String name;
  final String tagline;
  final List<String> benefits;
  final List<Color> colors;
}

/// What each plan promises.
///
/// Every line here has to be something the app actually does, checked against
/// the code that enforces it, because this screen is the one place where a
/// vague claim becomes a charge on somebody's card - and because App Review
/// opens the app, looks for what the subscription promised, and rejects the
/// build when the two disagree.
///
/// Each benefit below resolves to a gate in ProFeatures:
///
///   unlimited messages  -> coach_screen.dart, kCoachWeeklyLimit
///   every coach         -> ProFeatures.agentAvailable, agent_picker_screen
///   streaming music     -> ProFeatures.canStreamMusic, music_bar
///   feed customisation  -> ProFeatures.canCustomiseFeed, feed_screen
///   bigger memory       -> ProFeatures.memoryContext, coach_screen
///   editable memory     -> ProFeatures.canEditMemory, memory_screen
///
/// Nothing may be added here without a gate behind it first.
///
/// One paid tier, not two. There used to be a Plus and a Pro, and Pro's only
/// distinct benefit was "everything in Plus" - it unlocked nothing Plus did
/// not. Apple rejects an in-app purchase that does not deliver identifiable
/// content or functionality, and charging more for the same thing is a bad
/// deal besides. Pro is now the single paid tier and it carries the benefits
/// that are actually gated.
///
/// `plus` still exists as a tier on the server so that anybody who bought one
/// before keeps what they paid for. It is simply not sold any more.
const _tiers = [
  _TierInfo(
    id: 'pro',
    name: 'OurMynd Pro',
    tagline: 'Talk to Mynd as much as you need.',
    benefits: [
      'Unlimited messages with Mynd',
      'Every coach, not just Ember',
      'Search and stream any music while you focus',
      'Make the Feed about what you choose',
      'A memory ${ProFeatures.proMemoryContext ~/ ProFeatures.freeMemoryContext}x '
          'deeper, and editable by hand',
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
final _freeBenefits = [
  '5 messages a day with Mynd',
  'Ember, your starting coach',
  'Unlimited tasks, habits and notes',
  'Focus sessions, rooms and music from your device',
  'Your full planner and reminders',
  'Read your memory, but not edit it',
];

class _PaywallScreenState extends State<PaywallScreen>
    with WidgetsBindingObserver {
  String _interval = 'month'; // 'month' | 'year'
  // The only tier there is. Kept as state rather than inlined because the
  // card list and the plan lookup are both written for any number of tiers,
  // and a second one may come back once it has a feature of its own.
  String _tier = 'pro';

  /// Held, not looked up in dispose().
  ///
  /// dispose() used `context.read<PremiumProvider>()`, which is an inherited
  /// widget lookup on an element that has already been deactivated - "looking
  /// up a deactivated widget's ancestor is unsafe", thrown every time this
  /// screen is closed. Reading it once while the element is still mounted is
  /// the documented fix, and the provider outlives the screen anyway.
  late final PremiumProvider _premium;

  @override
  void initState() {
    super.initState();
    _premium = context.read<PremiumProvider>();
    WidgetsBinding.instance.addObserver(this);
    // After the frame, not during it.
    //
    // loadPlans notifies synchronously before its first await, so calling it
    // straight from initState marks this screen's provider dirty while the
    // tree is still being built - "setState() called during build", thrown on
    // every single open of this screen. It was invisible because nothing had
    // ever mounted the paywall outside the running app, where the framework
    // logs it and carries on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _premium.loadPlans();
      _premium.refresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _premium.clearPending();
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
      Toast.show(context, "You're premium now - enjoy");
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _manageSubscription() async {
    final premium = context.read<PremiumProvider>();
    Haptics.medium();
    // Apple owns the subscription on its own rail, so the only screen that can
    // cancel or change it is Apple's. Sending somebody to Stripe's portal
    // there would show them a page with nothing of theirs on it.
    final ok = StorePolicy.useStoreKit
        ? await premium.openAppleSubscriptions()
        : await premium.openBillingPortal();
    if (!ok && mounted) {
      Toast.show(context, "Couldn't open subscription settings - try again");
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
    try {
      final nowPremium = await premium.buy(plan.id);
      if (!mounted) return;
      if (nowPremium) {
        Haptics.success();
        Toast.show(context, "You're Pro now - enjoy");
        Navigator.of(context).maybePop();
      } else if (!StorePolicy.useStoreKit) {
        // The Stripe rail only opens a browser here; the result arrives on
        // resume. A false means the browser itself would not open.
        Toast.show(context, "Couldn't open checkout - try again");
      }
    } on IapException catch (e) {
      // Backing out of Apple's sheet is the most common thing that happens on
      // a paywall. Reporting it as a failure reads as "your card was
      // declined" to somebody who simply changed their mind.
      if (!mounted || e.failure == IapFailure.cancelled) return;
      Toast.show(context, e.message);
    }
  }

  Future<void> _restore() async {
    final premium = context.read<PremiumProvider>();
    Haptics.light();
    final nowPremium = await premium.restore();
    if (!mounted) return;
    if (nowPremium) {
      Haptics.success();
      Toast.show(context, 'Your subscription is back');
      Navigator.of(context).maybePop();
    } else {
      // Deliberately not an error. The commonest reason is that there is
      // nothing to restore, which is not something the person did wrong.
      Toast.show(context, 'No earlier purchase found on this Apple ID');
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
        else if (premium.plans.isEmpty)
          _StoreUnreachable(onRetry: () {
            premium.clearPlans();
            premium.loadPlans();
          })
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
                ? (StorePolicy.useStoreKit
                    ? 'Confirming…'
                    : 'Opening checkout…')
                : 'Subscribe to Pro',
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
          _RenewalNotice(interval: _interval),
          const SizedBox(height: 10),
          _LegalRow(onRestore: _restore),
        ],
      ],
    );
  }
}

/// What the store told us, when it told us nothing.
///
/// An empty paywall is read as a broken app, and on this rail it almost never
/// is: in the simulator it means no StoreKit configuration file is selected in
/// the run scheme, and on a device it means the product ids do not match App
/// Store Connect, the products are not Ready to Submit, or the Paid
/// Applications agreement is not Active. None of that is the person's problem,
/// so they get a retry rather than a diagnosis.
class _StoreUnreachable extends StatelessWidget {
  const _StoreUnreachable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 44),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 34, color: c.text2),
          const SizedBox(height: 14),
          Text(
            'Plans are unavailable right now',
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text, fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'The App Store did not answer. Nothing has been charged.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text2, fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 18),
          OmTappable(
            onTap: onRetry,
            feedback: OmTapFeedback.light,
            pressedScale: 0.97,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Try again',
                style: TextStyle(
                    color: c.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The auto-renewal disclosure.
///
/// Guideline 3.1.2 requires the length of the subscription and the fact that
/// it renews to be on the screen that sells it, not only in the terms - and a
/// paywall that does not say it is rejected. It also has to be true: Apple
/// takes the payment and Apple cancels it, so this points at the one place
/// that can.
class _RenewalNotice extends StatelessWidget {
  const _RenewalNotice({required this.interval});

  final String interval;

  @override
  Widget build(BuildContext context) {
    final period = interval == 'year' ? 'year' : 'month';
    final where = StorePolicy.useStoreKit
        ? 'Cancel any time in your Apple ID settings, at least 24 hours '
            'before it renews.'
        : 'Cancel any time from your account.';
    return Text(
      'Renews automatically every $period until cancelled. $where',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: context.omColors.text2,
        fontSize: 11.5,
        height: 1.45,
      ),
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
                  selected ? Icons.check_circle_rounded : Icons.circle_outlined,
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
    // Named from what they actually hold. Plus is withdrawn but not revoked,
    // so somebody who bought one still sees it called by its name rather than
    // being told they are on a tier they never chose.
    final name = tier == 'plus' ? 'OurMynd Plus' : 'OurMynd Pro';

    // One list, because there is one paid tier and the server grants the same
    // entitlement for either: isPremium checks only that the tier is not free.
    //
    // This used to merge the Plus and Pro benefit lists, reading them out of
    // _tiers by id. With Plus gone from _tiers that lookup throws, and it
    // threw on the screen a paying subscriber opens to manage their
    // subscription - so the one person guaranteed to see it was somebody who
    // had already given us money.
    final features = _tiers.first.benefits;

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
          StorePolicy.useStoreKit
              ? 'Apple handles the payment, so changing or cancelling happens '
                  'in your Apple ID settings. This opens that screen.'
              : 'Update your payment details or cancel anytime.',
          textAlign: TextAlign.center,
          style: TextStyle(color: c.text2, fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton(
      {required this.label, required this.onTap, this.busy = false});

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

/// Restore, privacy, terms - all three of which have to work.
///
/// They were three pieces of inert text. Apple requires functional links to
/// the terms and the privacy policy on the screen that sells a subscription
/// (Guideline 3.1.2), and requires a working restore for anybody who has
/// already paid and reinstalled; a label that looks like a link and does
/// nothing fails both, and reads as a broken app besides. Legal.open already
/// existed and nothing was calling it from here.
class _LegalRow extends StatelessWidget {
  const _LegalRow({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    // Underlined, because a tappable word that is only a shade darker is not
    // discoverable as a link - and these are the ones a reviewer looks for.
    final style = TextStyle(
      color: c.text2,
      fontSize: 11.5,
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
      decorationColor: c.text2.withValues(alpha: 0.5),
    );

    Widget link(String label, VoidCallback onTap) => OmTappable(
          onTap: onTap,
          feedback: OmTapFeedback.light,
          pressedScale: 0.96,
          child: Padding(
            // The text is 11.5pt, so the row needs padding of its own to reach
            // a 44pt tap target.
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            child: Text(label, style: style),
          ),
        );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        link('Restore Purchase', onRestore),
        link('Privacy Policy', () => Legal.openPrivacy(context)),
        link('Terms of Use', () => Legal.openTerms(context)),
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
