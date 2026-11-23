/// What a Pro subscription actually unlocks.
///
/// One place, read by both the paywall and the gates, because those two
/// drifting apart is a rejection rather than a bug: App Review opens the app,
/// looks for what the subscription said it would get, and refuses the build
/// when the two disagree. A benefit listed on the paywall has to resolve to a
/// constant here, and a constant here has to be enforced somewhere.
///
/// Entitlement itself is NOT decided here. It comes from the server through
/// PremiumProvider.isPremium; this only says what the answer unlocks.
abstract final class ProFeatures {
  /// The one coach available without a subscription.
  ///
  /// Ember rather than "the first in the list", so that reordering Agent.all
  /// cannot quietly change which agent is free and strand somebody who was
  /// talking to it yesterday.
  static const freeAgentId = 'ember';

  /// Parked thoughts handed to the coach as context, free and paid.
  ///
  /// Free stays at what it has always been. The gap is made by raising Pro,
  /// not by lowering free: every free user already has five, and taking some
  /// away to manufacture an upsell is a worse trade than the upsell is worth.
  static const freeMemoryContext = 5;
  static const proMemoryContext = 20;

  static bool agentAvailable(String id, {required bool premium}) =>
      premium || id == freeAgentId;

  static int memoryContext({required bool premium}) =>
      premium ? proMemoryContext : freeMemoryContext;

  /// Music from the internet - a searched track or a pasted stream link.
  /// Files already on the device play on any plan, so a free user is never
  /// left with silence.
  static bool canStreamMusic({required bool premium}) => premium;

  /// Editing the paragraph the Feed is generated from.
  static bool canCustomiseFeed({required bool premium}) => premium;

  /// Editing the coach's memory of you by hand. Reading it is always allowed.
  static bool canEditMemory({required bool premium}) => premium;
}
