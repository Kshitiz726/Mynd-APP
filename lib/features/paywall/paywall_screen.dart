import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/toast.dart';
import '../../widgets/om_switch.dart';
import '../../widgets/om_tappable.dart';

/// The paywall, built on the reference: a quiet screen with the benefits as a
/// short tick list, a trial toggle, two priced cards, and one button.
///
/// Two screens, in the order the reference has them. Tapping Continue with the
/// trial on does not charge anything; it explains what is about to happen and
/// when, which is the entire content of the second screen. A subscription
/// someone did not realise they were starting is a refund and a bad review, so
/// the timeline earns its extra tap.
class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key});

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

/// One purchasable plan.
class _Plan {
  const _Plan({
    required this.id,
    required this.label,
    required this.price,
    this.badge,
  });

  final String id;
  final String label;
  final String price;
  final String? badge;
}

const _plans = [
  _Plan(id: 'yearly', label: 'Yearly', price: r'$59.99/year', badge: '-50%'),
  _Plan(id: 'monthly', label: 'Monthly', price: r'$9.99/month'),
];

const _benefits = [
  'Unlimited AI coaching',
  'Unlimited goals and plans',
  'No ads, ever',
];

/// This screen takes its colours from the app, like every other screen.
///
/// It used to be a fixed dark slab, on the theory that a paywall should look
/// deliberate. In practice it looked like a different product bolted on at the
/// exact moment you are asking someone to trust you with money. Continuity is
/// the more valuable signal: the offer arrives in the same room as everything
/// else, so the only thing that changes is what is being said.

class _PaywallScreenState extends State<PaywallScreen> {
  String _selected = 'yearly';
  bool _trial = true;

  _Plan get _selectedPlan => _plans.firstWhere((p) => p.id == _selected);

  void _continue() {
    Haptics.medium();
    if (_trial) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
            builder: (_) => _TrialExplainer(plan: _selectedPlan)),
      );
    } else {
      Toast.show(context, 'Billing is not wired up yet');
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
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
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
                  children: [
                    const SizedBox(height: 12),
                    Text(
                      'Unlock Premium',
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
                      'Enjoy these benefits when you upgrade\nto the premium plan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text2,
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 30),
                    for (final b in _benefits)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_rounded,
                                size: 20, color: c.primary),
                            const SizedBox(width: 12),
                            Text(
                              b,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 22),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Enable 7-day free trial',
                            style: TextStyle(
                              color: c.text,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        OmSwitch(
                          value: _trial,
                          onChanged: (v) {
                            Haptics.select();
                            setState(() => _trial = v);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    for (final p in _plans)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PlanCard(
                          plan: p,
                          selected: _selected == p.id,
                          onTap: () {
                            Haptics.select();
                            setState(() => _selected = p.id);
                          },
                        ),
                      ),
                    const SizedBox(height: 14),
                    Text(
                      _trial
                          ? 'No charges yet. Cancel anytime.'
                          : 'Cancel anytime.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text2,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CtaButton(label: 'Continue', onTap: _continue),
                    const SizedBox(height: 18),
                    const _LegalRow(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The second screen: what the trial actually does, on a dated timeline.
class _TrialExplainer extends StatelessWidget {
  const _TrialExplainer({required this.plan});

  final _Plan plan;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
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
                child: _CloseButton(
                  // Closes the whole paywall, not just this page. Backing out of
                  // an explanation into the offer you just left is a maze.
                  onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 16),
                  children: [
                    const SizedBox(height: 16),
                    Text(
                      'How your free\ntrial works',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 30,
                        height: 1.2,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 40),
                    const _Step(
                      icon: Icons.lock_open_rounded,
                      title: 'Today',
                      body: 'Unlock access to all premium features',
                    ),
                    const _Step(
                      icon: Icons.notifications_rounded,
                      title: 'Day 5',
                      body: 'Get a reminder that your trial is about to end',
                    ),
                    const _Step(
                      icon: Icons.star_rounded,
                      title: 'Day 7',
                      body: 'Your subscription starts. Cancel anytime before.',
                      last: true,
                    ),
                    const SizedBox(height: 40),
                    Text(
                      'Free access for 7 days, then ${plan.price.replaceAll('/', ' per ')}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.text2,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _CtaButton(
                      label: 'Start 7-Day Free Trial',
                      onTap: () {
                        Haptics.success();
                        Toast.show(context, 'Billing is not wired up yet');
                      },
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: OmTappable(
                        onTap: () => Navigator.of(context).maybePop(),
                        feedback: OmTapFeedback.none,
                        pressedScale: 0.96,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 16),
                          child: Text(
                            'View All Plans',
                            style: TextStyle(
                              color: c.primary,
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One dated moment on the trial timeline, joined to the next by a rail.
class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.title,
    required this.body,
    this.last = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return Stack(
      children: [
        // The rail runs from under one icon to the top of the next, whatever
        // height the row turns out to be. A fixed 34px stub could not reach:
        // the gap between icons is set by the wrapping body text, so the line
        // stopped in mid-air and the timeline read as three loose blocks.
        // Positioned against the Row means it is measured, not guessed.
        if (!last)
          Positioned(
            left: 21,
            width: 2,
            top: 50,
            bottom: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Tinted, not grey. At two pixels a neutral hairline reads as
                // a rendering artefact; borrowing the icons' own colour makes
                // the three moments look like one timeline.
                color: c.primary.withValues(alpha: 0.28),
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.primaryTint,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 20, color: c.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 4, bottom: last ? 0 : 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        color: c.text2,
                        fontSize: 13.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard(
      {required this.plan, required this.selected, required this.onTap});

  final _Plan plan;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.98,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: selected ? c.primaryTint : c.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? c.primary : c.border,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              size: 22,
              color: selected ? c.primary : c.text2,
            ),
            const SizedBox(width: 12),
            Text(
              plan.label,
              style: TextStyle(
                color: c.text,
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (plan.badge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.primary.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  plan.badge!,
                  style: TextStyle(
                    color: c.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
            const Spacer(),
            Text(
              plan.price,
              style: TextStyle(
                color: c.text,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  const _CtaButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: onTap,
      feedback: OmTapFeedback.none,
      pressedScale: 0.97,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // The CTA is the app's own primary button, white on violet, so the
          // one control that takes money looks like every other control the
          // person has already learned to trust. Dark-on-bright was a holdover
          // from the cyan reference and read as a disabled button here.
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
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w800,
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
    final style = TextStyle(
      color: context.omColors.text2,
      fontSize: 11.5,
    );
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
