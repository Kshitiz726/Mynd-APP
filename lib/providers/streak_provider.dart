import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Consecutive days you showed up.
///
/// Two numbers on Home wore a flame icon and neither was a streak: the
/// top-right pill was a "berries" momentum score (`done * 10 + goals * 20`) and
/// the badge under the logo was the count of tasks finished today. Both reset
/// every midnight and neither survived a restart, so the flame was promising a
/// history the app was not keeping.
///
/// The rules, decided rather than inherited:
///
///  - **A day counts if you did either thing** - logged a mood check-in, or
///    completed any task. Two ways to keep a streak alive is deliberate: on the
///    days you have nothing in you, saying so should be enough.
///  - **A missed day breaks it.** No freezes, no repair. A streak you cannot
///    lose is not measuring anything.
///  - **Today is pending, not missing.** Until you have done either thing the
///    streak still shows its count, with today marked as not-yet rather than
///    broken - dropping the number to zero at midnight would punish people for
///    not having started their morning yet.
///  - **No retroactive completion.** There is deliberately no API here to mark
///    any day but today, so a streak means what it says.
///  - **Days are local.** A day is a calendar date in the device's own
///    timezone, so it rolls at local midnight and travelling does not rewrite
///    history.
class StreakProvider extends ChangeNotifier {
  StreakProvider() {
    load();
  }

  static const _kDays = 'om_streak_days';

  /// Completed days as `yyyy-mm-dd`, in local time.
  ///
  /// Stored as date keys rather than timestamps on purpose: an instant would
  /// have to be re-interpreted in whatever timezone the phone is in when it is
  /// read back, and a day you completed does not stop having happened because
  /// you got on a plane.
  final Set<String> _days = <String>{};

  bool _loaded = false;
  bool get loaded => _loaded;

  static String keyFor(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool isComplete(DateTime day) => _days.contains(keyFor(day));

  bool get todayComplete => isComplete(DateTime.now());

  /// Today counts towards the streak but has not been earned yet.
  bool get todayPending => !todayComplete && currentStreak > 0;

  /// Consecutive completed days ending today.
  ///
  /// If today is not done yet the count runs to yesterday instead, which is the
  /// grace rule: the streak is intact until the day is actually missed, and a
  /// day is only missed once it is over.
  int get currentStreak {
    final now = DateTime.now();
    var cursor = DateTime(now.year, now.month, now.day);
    if (!_days.contains(keyFor(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
      // Neither today nor yesterday: the chain is broken, whatever came before.
      if (!_days.contains(keyFor(cursor))) return 0;
    }
    var n = 0;
    while (_days.contains(keyFor(cursor))) {
      n++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// The best run ever recorded, for the calendar's summary.
  int get longestStreak {
    if (_days.isEmpty) return 0;
    final sorted = _days.toList()..sort();
    var best = 1;
    var run = 1;
    DateTime? previous;
    for (final key in sorted) {
      final day = DateTime.parse(key);
      if (previous != null) {
        run = day.difference(previous).inDays == 1 ? run + 1 : 1;
      }
      if (run > best) best = run;
      previous = day;
    }
    return best;
  }

  int get totalDays => _days.length;

  /// Mark today done. Idempotent, and the only way a day is ever recorded.
  ///
  /// Persist first, notify second, and both after an await: this gets called
  /// from a ProxyProvider's update, which runs during a build, and notifying
  /// listeners synchronously from there is the "setState called during build"
  /// crash. The await moves it safely past the current frame.
  Future<void> markToday() async {
    final key = keyFor(DateTime.now());
    if (!_days.add(key)) return; // already counted; do not churn storage
    await _persist();
    notifyListeners();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      _days.addAll(p.getStringList(_kDays) ?? const []);
    } catch (e) {
      debugPrint('[streak] load failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_kDays, _days.toList()..sort());
    } catch (e) {
      debugPrint('[streak] save failed: $e');
    }
  }
}
