import 'package:flutter_test/flutter_test.dart';

import 'package:ourmynd/core/config/pro_features.dart';
import 'package:ourmynd/models/agent.dart';

/// What Pro sells has to be what Pro gates.
///
/// App Review opens the app, looks for the thing the subscription promised,
/// and rejects the build when it is already free. These pin the gaps rather
/// than the values, so changing a number is fine and closing a gap is not.
void main() {
  test('the free coach is a real agent', () {
    // ProFeatures names it by id. A typo, or a rename in Agent.all, would
    // otherwise lock every coach including the free one and leave a free user
    // unable to talk to anybody.
    expect(
      Agent.all.where((a) => a.id == ProFeatures.freeAgentId),
      hasLength(1),
      reason: 'freeAgentId does not match any shipped agent',
    );
  });

  test('free gets one coach, Pro gets all of them', () {
    final free =
        Agent.all.where((a) => ProFeatures.agentAvailable(a.id, premium: false));
    final paid =
        Agent.all.where((a) => ProFeatures.agentAvailable(a.id, premium: true));

    expect(free, hasLength(1), reason: 'free should reach exactly one coach');
    expect(paid, hasLength(Agent.all.length));
    // The gap is the product. If a future agent were added as free, this is
    // the test that notices before the paywall starts lying.
    expect(paid.length, greaterThan(free.length));
  });

  test('Pro memory context is bigger, and free is not cut to make it so', () {
    expect(ProFeatures.proMemoryContext,
        greaterThan(ProFeatures.freeMemoryContext));
    // Five is what every free user already had before Pro existed. Lowering
    // it would take something away from people who have it today, which is a
    // worse trade than the upsell is worth - so it is pinned, not merely
    // compared.
    expect(ProFeatures.freeMemoryContext, 5);
    expect(ProFeatures.memoryContext(premium: false),
        ProFeatures.freeMemoryContext);
    expect(ProFeatures.memoryContext(premium: true),
        ProFeatures.proMemoryContext);
  });

  test('every paid capability is actually withheld from free', () {
    // The whole point. A gate that returns true for everybody is a benefit
    // the paywall charges for and the app gives away.
    const gates = <String, bool Function({required bool premium})>{
      'canStreamMusic': ProFeatures.canStreamMusic,
      'canCustomiseFeed': ProFeatures.canCustomiseFeed,
      'canEditMemory': ProFeatures.canEditMemory,
    };
    for (final entry in gates.entries) {
      expect(entry.value(premium: true), isTrue, reason: entry.key);
      expect(entry.value(premium: false), isFalse,
          reason: '${entry.key} is not gated: free users already have it');
    }
  });
}
