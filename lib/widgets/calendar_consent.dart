import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import 'om_tappable.dart';

/// Permission to read somebody's calendar and to send parts of it onward.
///
/// Two separate things are being asked for here, and the OS sheet only covers
/// the first. iOS asks whether Mynd may read the calendar. It does not, and
/// cannot, ask the question that actually matters: when somebody asks Mynd
/// about their day, the title and time of each event are put into the prompt
/// and sent to Groq (see TurnContext, which writes
/// `- 14:00 <title> (from their calendar)` into the turn).
///
/// Event titles are not minor data. They say who somebody is meeting and often
/// why: a consultant's name, an interview, a court date, a funeral. They also
/// carry other people's names, who never agreed to anything. Guidelines
/// 5.1.1(i) and 5.1.2(i) require that disclosure before it happens, and it is
/// the guideline this app has already been rejected under once.
///
/// Asked before the OS sheet rather than after, because afterwards is too
/// late: by then the permission is granted and the only honest thing left to
/// offer is an apology.
abstract final class CalendarConsent {
  static const _kGranted = 'om_calendar_consent_granted';

  /// Cached so the common path - already answered yes - costs nothing.
  static bool? _cached;

  /// Where the events go, named rather than described. "A third party" is not
  /// a disclosure; it is a way of avoiding one.
  static const provider = 'Groq';

  static Future<bool> isGranted() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final p = await SharedPreferences.getInstance();
      return _cached = p.getBool(_kGranted) ?? false;
    } catch (_) {
      // Unreadable storage means unanswered, which means ask. Failing open
      // here would read a calendar nobody agreed to.
      return false;
    }
  }

  /// Forget the answer, for an account switch. The next account is a
  /// different person and has agreed to nothing.
  static Future<void> clear() async {
    _cached = null;
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kGranted);
    } catch (_) {/* the cache is cleared either way */}
  }

  static Future<void> _remember(bool granted) async {
    _cached = granted;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(_kGranted, granted);
    } catch (_) {/* holds for this session */}
  }

  /// Ask if we have not already. Returns true when the OS sheet may be raised.
  ///
  /// A "no" is not stored as a refusal that sticks: the sheet closes, nothing
  /// is connected, and pressing Connect again simply asks again. Somebody who
  /// tapped it to see what it was should not have to go hunting through
  /// settings to undo that.
  static Future<bool> ensure(BuildContext context) async {
    if (await isGranted()) return true;
    if (!context.mounted) return false;

    final allowed = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _CalendarConsentSheet(),
        ) ??
        false;

    if (!allowed) return false;
    await _remember(true);
    return true;
  }
}

class _CalendarConsentSheet extends StatelessWidget {
  const _CalendarConsentSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final t = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(26),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.event_rounded, size: 22, color: c.primary),
            ),
            const SizedBox(height: 14),
            Text('Before you connect your calendar',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'Mynd reads the events on the one calendar you pick, so it can '
              'plan around them and write your focus blocks back to it.',
              style: t.bodyMedium?.copyWith(color: c.text2, height: 1.5),
            ),
            const SizedBox(height: 12),
            // The part the OS sheet cannot say, and the part people do not
            // expect.
            Text(
              'When you ask Mynd about your day, the title and time of those '
              'events are sent to ${CalendarConsent.provider}, an AI company, '
              'to answer you. Event titles often say more than they look like '
              'they do - who you are meeting, and sometimes why.',
              style: t.bodyMedium?.copyWith(color: c.text2, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              'Nothing is read until you choose a calendar, and you can '
              'disconnect it at any time in Profile, Connections.',
              style: t.bodyMedium?.copyWith(color: c.text2, height: 1.5),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _SheetButton(
                    label: 'Not now',
                    filled: false,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SheetButton(
                    label: 'Allow',
                    filled: true,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetButton extends StatelessWidget {
  const _SheetButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    return OmTappable(
      onTap: () {
        Haptics.light();
        onTap();
      },
      feedback: OmTapFeedback.none,
      pressedScale: 0.97,
      child: Container(
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? c.primary : c.surfaceAlt,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            // Measured against the fill rather than assumed. A hardcoded
            // white here is only right while the fill happens to be dark.
            color: filled ? OmColors.onFill(c.primary) : c.text,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}
