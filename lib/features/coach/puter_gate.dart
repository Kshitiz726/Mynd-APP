import 'package:flutter/material.dart';

import '../../core/constants/app_spacing.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../widgets/fluid_orb.dart';
import '../../widgets/om_tappable.dart';
import 'puter_connect_screen.dart';

/// What you see instead of the chat when Puter is not connected yet.
///
/// The coach runs on Puter, and Puter is user-pays, so there is a one-time
/// sign-in before any of this works. That used to be a small chip in the corner
/// of a chat that could not answer you: you could type, wait, and get a timeout
/// with no idea why. Better to say the one true thing up front and give it the
/// whole screen.
///
/// It is deliberately the same face as the chat itself, the same orb at the
/// same size, so connecting reads as continuing rather than as a detour through
/// somebody else's product.
class PuterGate extends StatelessWidget {
  const PuterGate({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FluidOrb(size: 132),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'MYND',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 8,
                      color: c.primary,
                    ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your coach runs on Puter, so it needs a Puter account before '
                'it can talk to you.',
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: c.text2, height: 1.55),
              ),
              const SizedBox(height: 8),
              Text(
                'You only do this once.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: AppSpacing.xl),
              OmTappable(
                onTap: () {
                  Haptics.medium();
                  Navigator.of(context).push(
                    MaterialPageRoute<bool>(
                        builder: (_) => const PuterConnectScreen()),
                  );
                },
                feedback: OmTapFeedback.none,
                pressedScale: 0.97,
                child: Container(
                  height: 54,
                  width: double.infinity,
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
                  child: const Text(
                    'Sign in with Puter',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
