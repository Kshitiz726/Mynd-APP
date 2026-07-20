import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The primary bottom-navigation destinations, mirroring the prototype's
/// `.navbar` buttons: home · schedule · (+) · community · settings.
///
/// Focus and the coach are no longer destinations: they are things you *start*,
/// so they live behind the centre (+) and open as full-screen routes.
///
/// Icons come from **Lucide** - the one icon family used everywhere else in the
/// app - so the tab bar matches the rest of the UI. The selected tab is
/// distinguished by the nav bar's tinted "expanding pill" (icon + label), not by
/// swapping to a filled glyph, so [activeIcon] mirrors [icon].
enum AppTab {
  today(label: 'home', icon: LucideIcons.house),
  schedule(label: 'schedule', icon: LucideIcons.calendarDays),
  community(label: 'community', icon: LucideIcons.users),
  settings(label: 'settings', icon: LucideIcons.settings);

  const AppTab({required this.label, required this.icon});

  final String label;

  /// The tab's Lucide glyph (same for active/inactive - the pill marks active).
  final IconData icon;

  /// Kept for API compatibility with call sites; identical to [icon].
  IconData get activeIcon => icon;
}

/// Holds the selected tab so both the nav bar and in-content shortcuts (e.g.
/// the Home avatar opening "you") can drive navigation without prop-drilling.
class NavProvider extends ChangeNotifier {
  AppTab _tab = AppTab.today;
  AppTab _prev = AppTab.today;

  AppTab get tab => _tab;

  /// The tab we were on before the current one - lets immersive tabs (Coach,
  /// You) that hide the bottom bar offer a header "back" that returns there.
  AppTab get previous => _prev;
  int get index => AppTab.values.indexOf(_tab);

  void select(AppTab tab) {
    if (tab == _tab) return;
    _prev = _tab;
    _tab = tab;
    notifyListeners();
  }

  /// Return to the previously-selected tab (defaults to Today).
  void back() => select(_prev == _tab ? AppTab.today : _prev);

  void selectIndex(int index) => select(AppTab.values[index]);
}
