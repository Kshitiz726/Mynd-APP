/// Named routes for screens pushed on top of the tab shell (modals/details).
/// Tab destinations are handled by [NavProvider], not the router.
abstract final class AppRoutes {
  /// The tab shell. Deliberately NOT '/'.
  ///
  /// MaterialApp's `home` is registered in the route table under '/', and this
  /// app's `home` is the launch screen. While the shell was also named '/',
  /// `pushReplacementNamed(shell)` resolved to the launch screen instead: it
  /// started its timer, handed over to '/', and landed back on itself - the
  /// splash loop people hit right after signing in with Google. The launch
  /// screen worked around it by building the route directly, but every other
  /// caller (three in the login screen) still went through the name and still
  /// looped. Giving the shell a name of its own fixes it for all of them and
  /// leaves no way to reintroduce it.
  static const String shell = '/shell';
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
  static const String motivation = '/motivation';
}
