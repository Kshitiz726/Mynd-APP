import 'package:flutter/material.dart';

/// The primary bottom-navigation destinations: chat · feed · schedule · focus.
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
///
/// Both halves of every pair are the SAME glyph, outlined and filled, which is
/// why these are Material rather than the Lucide set used everywhere else in
/// the app. Lucide is outline-only, so each tab had to borrow a filled Material
/// icon for its selected state, and the two were never the same drawing: the
/// calendar changed from a dotted page to a grid and the newspaper to a sheet
/// of lines. A cross-fade can hide a change of weight. It cannot hide a change
/// of shape, so selecting a tab looked like the icon being swapped for a
/// different one.
enum AppTab {
  // Chat's pair is drawn by hand in the nav bar - Material has no circular
  // filled bubble - so these two are only the fallback for anywhere else that
  // reads them.
  coach(
      label: 'chat',
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded),
  feed(
      label: 'feed',
      icon: Icons.newspaper_outlined,
      activeIcon: Icons.newspaper_rounded),
  schedule(
      label: 'schedule',
      icon: Icons.calendar_month_outlined,
      activeIcon: Icons.calendar_month_rounded),
  focus(
      label: 'focus',
      icon: Icons.timer_outlined,
      activeIcon: Icons.timer_rounded);
  // Parked - the screens still exist, they are just off the bar:
  // today   -> its pieces moved to Feed (quote, do-this-now, mood) and
  //            Schedule (goals); Profile opens from the chat drawer's gear.
  // community(label: 'community', icon: Icons.groups_outlined, ...)

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
  AppTab _tab = AppTab.coach;
  AppTab _prev = AppTab.coach;

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
  void back() => select(_prev == _tab ? AppTab.coach : _prev);

  void selectIndex(int index) => select(AppTab.values[index]);
}
