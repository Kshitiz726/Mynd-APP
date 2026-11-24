import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/services/speech_service.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/haptics.dart';
import '../core/utils/om_icons.dart';
import 'om_tappable.dart';
import 'voice_consent.dart';

/// Where dictated words land in a field that may already have text in it.
///
/// Appending blindly is wrong twice over: it ignores where the caret actually
/// is, and it runs the new words into the old ones with no space, so dictating
/// after a half-typed sentence produced "buy milkand text mom". This inserts at
/// the caret, adds a space on whichever side needs one, and leaves the caret
/// after the words it just put in, so you can keep dictating or keep typing
/// without reaching for the field again.
///
/// A plain function rather than a method so the joining rules can be tested
/// without a mic, a WebView or a network.
TextEditingValue insertDictation(TextEditingValue value, String words) {
  final text = words.trim();
  if (text.isEmpty) return value;

  final old = value.text;
  // An invalid selection is what a field that has never been focused reports.
  // Treating its -1 as an offset would insert at the start, which is where the
  // words least belong.
  final sel = value.selection;
  final start = sel.isValid ? math.min(sel.start, old.length) : old.length;
  final end = sel.isValid ? math.min(sel.end, old.length) : old.length;

  final before = old.substring(0, start);
  final after = old.substring(end);

  final needsLeadingSpace =
      before.isNotEmpty && !before.endsWith(' ') && !before.endsWith('\n');
  final needsTrailingSpace =
      after.isNotEmpty && !after.startsWith(' ') && !after.startsWith('\n');

  final insert = '${needsLeadingSpace ? ' ' : ''}$text'
      '${needsTrailingSpace ? ' ' : ''}';
  final caret = start + insert.length - (needsTrailingSpace ? 1 : 0);

  return TextEditingValue(
    text: '$before$insert$after',
    selection: TextSelection.collapsed(offset: caret),
  );
}

/// What the button is doing. Each one looks different, because "is it
/// listening" is the only question anybody asks of a mic.
enum _Mic {
  idle,

  /// Tapped, but the mic is not open yet.
  ///
  /// This is its own state rather than part of [listening] because opening the
  /// mic is not instant and can not finish at all: the first tap of a session
  /// puts the OS permission dialog on screen, and the call behind it sits
  /// pending for as long as the user takes to answer. Showing the listening
  /// fill through that is the one lie a mic must never tell - it says the app
  /// is recording while nothing is being captured, and anything said into it
  /// is lost.
  opening,

  listening,

  /// Mic closed, words being written down.
  transcribing,
}

/// A mic that dictates into a text field, sized to sit in a composer.
///
/// The app already had voice, but only as its own full screen: you left what
/// you were writing, spoke, and came back. That is the right shape for dumping
/// a paragraph and the wrong one for a chat, where half of what you want to say
/// is already typed. This one records in place and inserts the transcript at
/// the caret, so speaking is just another way to fill the field you are already
/// looking at.
///
/// Errors are handed to [onError] rather than shown here or put in a SnackBar.
/// A mic that is 40px across has nowhere to print a sentence, and a SnackBar
/// draws at the bottom of the Scaffold - underneath any sheet that is still
/// covering it, which is how the voice failures on the brain dump came to be
/// invisible.
class OmMicButton extends StatefulWidget {
  const OmMicButton({
    super.key,
    required this.controller,
    this.size = 40,
    this.onError,
    this.onTranscript,
    this.onListeningChanged,
    this.enabled = true,
  });

  /// The field the words go into.
  final TextEditingController controller;

  /// Diameter of the tap target. The bloom grows outside it, so a parent does
  /// not need to leave room for the glow.
  final double size;

  /// A sentence for the user, in the host surface's own error slot.
  final ValueChanged<String>? onError;

  /// The transcript, after it has been inserted. For a host that wants to act
  /// on it as well, such as sending it straight away.
  final ValueChanged<String>? onTranscript;

  /// So a host can soften or hide its own controls while the mic has the floor.
  final ValueChanged<bool>? onListeningChanged;

  final bool enabled;

  @override
  State<OmMicButton> createState() => _OmMicButtonState();
}

class _OmMicButtonState extends State<OmMicButton>
    with SingleTickerProviderStateMixin {
  final _stt = SpeechService.instance;

  _Mic _phase = _Mic.idle;

  /// Smoothed loudness. The raw meter is jumpy enough to read as a flicker, and
  /// a mic that flickers looks broken rather than sensitive.
  double _level = 0;

  /// One continuous clock, started when listening begins and stopped when it
  /// ends. It drives a slow breath underneath the loudness, so a silent pause
  /// still looks like something that is listening rather than something that
  /// has frozen.
  ///
  /// Built in [initState], NOT as a `late final` initialiser. A lazy field is
  /// only created on first touch, and for a composer that was never dictated
  /// into the first touch is `dispose` - where attaching a ticker does an
  /// inherited-widget lookup on an element that has already been deactivated,
  /// and throws. Every teardown of a chat screen with an unused mic in it
  /// would have asserted.
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
  }

  @override
  void dispose() {
    // Only if it is ours. Tearing down a composer must not cut off a recording
    // that some other surface started.
    if (_phase == _Mic.listening || _phase == _Mic.opening) _stt.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _setPhase(_Mic p) {
    if (!mounted) return;
    setState(() => _phase = p);
    final listening = p == _Mic.listening;
    listening ? _pulse.repeat() : _pulse.stop();
    widget.onListeningChanged?.call(listening);
  }

  Future<void> _start() async {
    // The service holds one mic for the whole app. If another surface is
    // already recording, saying so beats silently stealing its audio.
    if (_stt.isRecording) {
      widget.onError?.call('Something else is already using the microphone.');
      return;
    }

    // Asked here, at the button, rather than by each screen that hosts one.
    //
    // Dictation uploads a recording of the person's voice to Groq. Whether
    // they have agreed to that is a property of pressing this button, not of
    // which screen it happens to be on - and leaving it to the hosts is how
    // the brain dump ended up with a microphone that uploaded audio with
    // nothing asked, while the chat's was covered only because the whole
    // chat sits behind the consent screen. One gate, at the only place the
    // microphone can be opened.
    if (!await VoiceConsent.ensure(context)) return;
    if (!mounted) return;

    Haptics.light();
    _setPhase(_Mic.opening);

    // Wrapped, because opening the mic can throw rather than return false.
    // The permission check runs on a platform channel, and a channel that is
    // not there - an unsupported platform, a test host, a plugin that failed
    // to register - throws out of the service. Unhandled, that left the button
    // stuck in its listening fill with no recording behind it, which is the
    // worst of both: it says it is hearing you and it is not.
    bool ok;
    try {
      ok = await _stt.startRecording(onLevel: _onLevel);
    } catch (e) {
      ok = false;
    }
    if (!mounted) return;
    // Cancelled while the dialog was up. Not a failure, and not a reason to
    // claim the floor that the user has just given back.
    if (_phase != _Mic.opening) return;
    if (!ok) {
      _setPhase(_Mic.idle);
      Haptics.error();
      // The service's own words where it has any: a missing grant, a grant
      // refused for good, and a recorder that would not open need three
      // different things from the user.
      widget.onError?.call(_stt.lastError ?? 'Microphone unavailable.');
      return;
    }
    _setPhase(_Mic.listening);
    Haptics.light();
  }

  /// Give up on a mic that has not opened yet.
  ///
  /// Without this a permission dialog left unanswered - or a recorder that
  /// never comes back - leaves the button pinned in a state it cannot leave.
  Future<void> _abandon() async {
    if (_phase != _Mic.opening) return;
    _setPhase(_Mic.idle);
    try {
      await _stt.cancel();
    } catch (_) {}
  }

  void _onLevel(double l) {
    if (!mounted || _phase != _Mic.listening) return;
    setState(() => _level = _level * 0.62 + l * 0.38);
  }

  Future<void> _stop() async {
    if (_phase != _Mic.listening) return;
    Haptics.light();
    _setPhase(_Mic.transcribing);
    setState(() => _level = 0);

    String text;
    try {
      text = await _stt.stopAndTranscribe();
    } catch (e) {
      text = '';
    }
    if (!mounted) return;
    _setPhase(_Mic.idle);

    if (text.trim().isEmpty) {
      Haptics.error();
      // The service's reason where it has one. Empty means "nothing usable
      // came back", and that covers a mumble, an expired session and a
      // refusal to send the audio at all - three things the user has to do
      // three different things about.
      widget.onError?.call(
          _stt.lastError ?? "Didn't catch that. Try again a bit closer.");
      return;
    }

    widget.controller.value = insertDictation(widget.controller.value, text);
    Haptics.success();
    widget.onTranscript?.call(text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final listening = _phase == _Mic.listening;
    final opening = _phase == _Mic.opening;
    final busy = _phase == _Mic.transcribing || opening;
    final s = widget.size;

    // Filled while it has the floor, ghosted while it does not. The fill is the
    // whole signal that recording is live, so it is the brand colour rather
    // than a red dot bolted on beside it.
    final fill = listening
        ? c.primary
        : busy
            ? c.primary.withValues(alpha: 0.18)
            : c.text2.withValues(alpha: 0.10);
    final glyph = listening
        ? OmColors.onFill(c.primary)
        : busy
            ? c.primary
            : c.text2;

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: s,
      height: s,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: busy
          ? SizedBox(
              width: s * 0.42,
              height: s * 0.42,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(c.primary),
              ),
            )
          // Crossfaded rather than swapped, so the glyph does not pop at the
          // instant the fill is still moving under it.
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Icon(
                OmIcons.byName(listening ? 'check' : 'mic'),
                key: ValueKey<bool>(listening),
                size: s * 0.46,
                color: glyph,
              ),
            ),
    );

    return Semantics(
      label: switch (_phase) {
        _Mic.idle => 'dictate',
        _Mic.opening => 'opening the microphone, tap to cancel',
        _Mic.listening => 'listening, tap to finish',
        _Mic.transcribing => 'writing down what you said',
      },
      button: true,
      enabled: widget.enabled && _phase != _Mic.transcribing,
      child: SizedBox(
        width: s,
        height: s,
        child: OmTappable(
          // Tap to start, tap to finish. Hold-to-talk loses the whole sentence
          // if a thumb slips, and a brain dump is the one thing nobody wants to
          // say twice.
          onTap: widget.enabled
              ? switch (_phase) {
                  // A second tap while it is opening abandons it, so an
                  // unanswered permission dialog is not a dead end.
                  _Mic.opening => _abandon,
                  _Mic.listening => _stop,
                  _Mic.transcribing => null,
                  _Mic.idle => _start,
                }
              : null,
          enabled: widget.enabled && _phase != _Mic.transcribing,
          feedback: OmTapFeedback.none,
          pressedScale: 0.9,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              if (listening)
                // Behind the button and outside its box, so the halo can swell
                // without the tap target moving under a resting thumb.
                Positioned.fill(
                  child: IgnorePointer(
                    child: RepaintBoundary(
                      child: AnimatedBuilder(
                        animation: _pulse,
                        builder: (context, _) => CustomPaint(
                          painter: _BloomPainter(
                            colour: c.primary,
                            level: _level,
                            breath: _pulse.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              button,
            ],
          ),
        ),
      ),
    );
  }
}

/// The soft halo around a live mic.
///
/// Stepped rings of falling alpha rather than a [MaskFilter.blur]: the blur is
/// the single most expensive call in a Flutter paint, and at this size five
/// concentric circles are indistinguishable from it while costing nothing. No
/// shader is allocated either, so there is nothing per-frame to garbage.
class _BloomPainter extends CustomPainter {
  _BloomPainter({
    required this.colour,
    required this.level,
    required this.breath,
  });

  final Color colour;

  /// Smoothed loudness, 0..1.
  final double level;

  /// 0..1 from the continuous clock.
  final double breath;

  static const _rings = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final base = size.shortestSide / 2;

    // The breath keeps a silent mic alive; the level is what makes it feel like
    // it can hear you. Both are gentle on purpose - this sits beside a text
    // field, not on a stage.
    final swell = math.sin(breath * 2 * math.pi) * 0.5 + 0.5;
    final reach = base * (1.18 + swell * 0.10 + level * 0.62);

    for (var i = _rings; i >= 1; i--) {
      final t = i / _rings;
      canvas.drawCircle(
        centre,
        base + (reach - base) * t,
        Paint()
          ..color = colour.withValues(
              alpha: (0.16 + level * 0.14) * (1 - t) * (1 - t)),
      );
    }
  }

  @override
  bool shouldRepaint(_BloomPainter old) =>
      old.level != level || old.breath != breath || old.colour != colour;
}
