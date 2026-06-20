/// Centralised animation timings. When "reduce motion" is enabled these are
/// collapsed to [instant] by the relevant widgets / page transitions.
abstract final class AppDurations {
  static const Duration instant = Duration.zero;
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 250);
  static const Duration slow = Duration(milliseconds: 400);
  static const Duration pageTransition = Duration(milliseconds: 300);
}
