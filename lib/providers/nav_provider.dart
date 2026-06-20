import 'package:flutter/material.dart';

/// The primary bottom-navigation destinations, mirroring the prototype's
/// `.navbar` buttons: today · focus · community · alerts · coach · you.
///
/// Each tab carries an outline glyph (inactive) and a solid glyph (active) so
/// the bar can do a Facebook-style fill on the selected tab. Material's rounded
import 'package:flutter/cupertino.dart';

enum AppTab {
  today(label: 'today', icon: CupertinoIcons.home, activeIcon: CupertinoIcons.house_fill),
  focus(label: 'focus', icon: CupertinoIcons.timer, activeIcon: CupertinoIcons.timer_fill),
  community(label: 'community', icon: CupertinoIcons.group, activeIcon: CupertinoIcons.group_solid),
  alerts(label: 'alerts', icon: CupertinoIcons.bell, activeIcon: CupertinoIcons.bell_fill),
  coach(label: 'coach', icon: CupertinoIcons.chat_bubble, activeIcon: CupertinoIcons.chat_bubble_fill),
  you(label: 'you', icon: CupertinoIcons.person, activeIcon: CupertinoIcons.person_solid);

  const AppTab({required this.label, required this.icon, required this.activeIcon});

  final String label;

  /// Outline glyph shown when the tab is inactive.
  final IconData icon;

  /// Solid glyph shown when the tab is active (the filled "Facebook" state).
  final IconData activeIcon;
}

/// Holds the selected tab so both the nav bar and in-content shortcuts (e.g.
/// the Home avatar opening "you") can drive navigation without prop-drilling.
class NavProvider extends ChangeNotifier {
  AppTab _tab = AppTab.today;
  AppTab _prev = AppTab.today;

  AppTab get tab => _tab;

  /// The tab we were on before the current one — lets immersive tabs (Coach,
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
