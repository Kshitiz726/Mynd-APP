import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import '../providers/ai_consent_provider.dart';
import 'om_tappable.dart';

/// Permission to send a recording of somebody's voice to a third party.
///
/// Dictation does not happen on the device. The audio is uploaded to Groq,
/// transcribed there and sent back, which means a recording of the person's
/// voice - and whatever they happened to say near the microphone - leaves the
/// phone and reaches a company they have never heard of.
///
/// That is a disclosure Apple requires before it happens, not after
/// (Guidelines 5.1.1(i) and 5.1.2(i)), and it is the guideline this app has
/// already been rejected under once. Text was gated; voice was not, so the
/// brain dump's microphone uploaded audio with nothing asked. The chat's
/// microphone only escaped because the whole chat sits behind the AI consent
/// screen.
///
/// Asked separately from the text disclosure on purpose. A voice recording is
/// a different kind of thing to a typed sentence: it carries who is speaking
/// and whoever else is in the room, and somebody who agreed to have their
/// words sent has not necessarily agreed to that.
abstract final class VoiceConsent {
  static const _kGranted = 'om_voice_consent_granted';

  /// Cached so the common path - already answered yes - costs nothing.
  static bool? _cached;

  /// Where the recording goes, named rather than described. "A third party"
  /// is not a disclosure; it is a way of avoiding one.
  static const provider = 'Groq';

  static Future<bool> isGranted() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final p = await SharedPreferences.getInstance();
      return _cached = p.getBool(_kGranted) ?? false;
    } catch (_) {
      // Unreadable storage means unanswered, which means ask. Failing open
      // here would upload audio nobody agreed to.
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

  /// Ask if we have not already. Returns true when dictation may proceed.
  ///
  /// A "no" is not remembered as a refusal that sticks: the sheet simply
  /// closes and the microphone does nothing, so pressing it again asks again.
  /// Somebody who tapped the mic by accident should not have to go hunting
  /// through settings to undo it.
  static Future<bool> ensure(BuildContext context) async {
    if (await isGranted()) return true;
    if (!context.mounted) return false;

    final allowed = await showModalBottomSheet<bool>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => const _VoiceConsentSheet(),
        ) ??
        false;

    if (!allowed) return false;
    await _remember(true);

    // The same answer the server's gate reads. Dictation is a message to the
    // AI by another route, so agreeing to it here has to count there too -
    // otherwise the transcription request is refused by our own middleware
    // with a 403 and the microphone looks broken.
    final ai = AiConsentProvider.instance;
    if (!ai.granted) {
      await ai.grant(source: 'voice', company: provider);
    }
    return true;
  }
}

class _VoiceConsentSheet extends StatelessWidget {
  const _VoiceConsentSheet();

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
              child: Icon(Icons.mic_rounded, size: 22, color: c.primary),
            ),
            const SizedBox(height: 14),
            Text('Before you use the microphone',
                style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'Your voice is not turned into text on this phone. The '
              'recording is sent to ${VoiceConsent.provider}, an AI company, '
              'transcribed there, and the text comes back here.',
              style: t.bodyMedium?.copyWith(color: c.text2, height: 1.5),
            ),
            const SizedBox(height: 12),
            // Said plainly, because it is the part people do not expect: a
            // microphone picks up the room, not just the person holding it.
            Text(
              'That means anything audible while you are recording leaves '
              'your phone, including other people nearby. Only the words you '
              'dictate are kept by us, in the note or message you put them '
              'in.',
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
            const SizedBox(height: 8),
            Center(
              child: Text(
                'You can withdraw this in Profile, AI and your data.',
                style: t.bodySmall?.copyWith(color: c.text2),
              ),
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
