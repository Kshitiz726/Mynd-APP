import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The primary bottom-navigation destinations, mirroring the prototype's
/// `.navbar` buttons: home · schedule · (+) · community · settings.
///
/// Focus and the coach are no longer destinations: they are things you *start*,
/// so they live behind the centre (+) and open as full-screen routes.
///
/// Resting icons come from **Lucide** - the one icon family used everywhere
/// else in the app. The *selected* tab swaps to a solid glyph: an outline that
/// only changes colour is easy to lose at a glance, and a filled shape reads as
/// "you are here" from the corner of the eye, which is the whole job of a tab
/// bar. The pair is drawn as a cross-fade so nothing pops.
enum AppTab {
  today(label: 'home', icon: LucideIcons.house, activeIcon: Icons.home_rounded),
  schedule(
      label: 'schedule',
      icon: LucideIcons.calendarDays,
      activeIcon: Icons.calendar_month_rounded),
  community(label: 'community', icon: LucideIcons.users, activeIcon: Icons.people_rounded),
  settings(label: 'settings', icon: LucideIcons.settings, activeIcon: Icons.settings_rounded);

  const AppTab({required this.label, required this.icon, required this.activeIcon});

  final String label;

  /// The resting (outline) glyph.
  final IconData icon;

  /// The solid glyph shown while this tab is selected.
  final IconData activeIcon;
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
