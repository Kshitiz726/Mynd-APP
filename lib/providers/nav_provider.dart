import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// The primary bottom-navigation destinations: home · schedule · focus · chat.
///
/// Focus and the coach used to be things you *started* from a centre (+) and
/// opened as full-screen routes; they are first-class destinations now, and the
/// (+) is gone with them. Community and settings are parked while we focus on
/// these four: settings still opens from the profile avatar on Home, and the
/// community screen is left in the codebase, just off the bar (see the
/// commented entries below).
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
  focus(
      label: 'focus',
      icon: LucideIcons.timer,
      activeIcon: Icons.timer_rounded),
  coach(
      label: 'chat',
      icon: LucideIcons.messageCircle,
      activeIcon: Icons.chat_bubble_rounded);
  // Parked for now - keep the code, off the bar:
  // community(label: 'community', icon: LucideIcons.users, activeIcon: Icons.people_rounded),
  // settings(label: 'settings', icon: LucideIcons.settings, activeIcon: Icons.settings_rounded);

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
