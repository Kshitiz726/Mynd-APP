/// Named routes for screens pushed on top of the tab shell (modals/details).
/// Tab destinations are handled by [NavProvider], not the router.
abstract final class AppRoutes {
  static const String shell = '/';
  static const String splash = '/splash';
  static const String login = '/login';
  static const String profile = '/profile';
  static const String paywall = '/paywall';
  static const String notes = '/notes';
  static const String reminders = '/reminders';
  static const String focusActive = '/focus/active';
  /// Focus and coach are started from the nav bar's (+), not browsed to.
  static const String focus = '/focus';
  static const String coach = '/coach';
}
