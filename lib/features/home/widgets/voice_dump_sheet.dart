import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_spacing.dart';
import '../../../core/services/live_dictation.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/haptics.dart';
import '../../../core/utils/om_icons.dart';
import '../../../providers/task_provider.dart';
import '../../../widgets/glow_ring.dart';
import '../../../widgets/om_tappable.dart';
import 'brain_dump_sheet.dart';

/// Tap the Home orb → talk → tasks.
///
/// The spoken version of Brain Dump: it listens on-device, shows the words as
/// they land, and runs the finished transcript through the same Groq extraction
/// the typed sheet uses, so speaking "buy milk, text mom, finish the report"
/// drops three tasks into today just like typing it would.
void showVoiceDumpSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const VoiceDumpSheet(),
  );
}

enum _Vp { listening, empty, processing, done, error }

class VoiceDumpSheet extends StatefulWidget {
  const VoiceDumpSheet({super.key});

  @override
  State<VoiceDumpSheet> createState() => _VoiceDumpSheetState();
}

class _VoiceDumpSheetState extends State<VoiceDumpSheet> {
  final _stt = LiveDictation.instance;

  _Vp _phase = _Vp.listening;
  String _text = '';
  int _added = 0;
  String? _error;
  double _level = 0;

  bool _turnEnding = false;

  // Dead simple, on purpose: the mic keeps recording the WHOLE time the sheet is
  // open and only stops when you tap "done". No pause detection, no auto-break,
  // no interruption - your full audio is captured start to finish, then
  // transcribed and run through the same Brain Dump extraction.

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _stt.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _phase = _Vp.listening;
      _text = '';
      _error = null;
      _level = 0;
    });
    _turnEnding = false;
    Haptics.medium();
    // Live now, like the chat composer. The words appear while you are still
    // talking, so a microphone that is not working is visible immediately
    // rather than at the end of a paragraph you then have to say again.
    final ok = await _stt.start(
      onText: (text, isFinal) {
        if (!mounted || _phase != _Vp.listening) return;
        setState(() => _text = text);
        // The recogniser ends the session itself after a pause. Treating that
        // as "done" is what lets somebody simply stop talking.
        if (isFinal && !_stt.isListening) unawaited(_stopAndProcess());
      },
      onLevel: _onLevel,
    );
    if (!ok && mounted) {
      setState(() {
        _phase = _Vp.error;
        // The service's own words: a missing grant, a refused one, no network
        // and a busy microphone are different problems with different fixes,
        // and one fixed sentence was wrong for most of them.
        _error = _stt.lastError ?? 'Microphone unavailable.';
      });
      return;
    }
  }

  // Just drives the halo's swell - no pause detection.
  void _onLevel(double l) {
    if (!mounted || _phase != _Vp.listening) return;
    setState(() => _level = _level * 0.6 + l * 0.4);
  }

  Future<void> _stopAndProcess() async {
    if (_turnEnding) return;
    _turnEnding = true;
    setState(() => _phase = _Vp.processing);
    // Nothing to transcribe at the end any more: the text has been arriving
    // all along, so stopping is just stopping.
    await _stt.stop();
    if (!mounted) return;
    await _process(_text);
  }

  Future<void> _process(String text) async {
    if (!mounted) return;
    final clean = text.trim();
    if (clean.isEmpty) {
      setState(() => _phase = _Vp.empty);
      return;
    }
    setState(() {
      _text = clean;
      _phase = _Vp.processing;
    });
    final tp = context.read<TaskProvider>();
    try {
      final n = await processBrainDumpText(clean, tp);
      if (!mounted) return;
      Haptics.success();
      setState(() {
        _added = n;
        _phase = _Vp.done;
      });
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _phase = _Vp.error;
          // The reason, not just the fact. This was `catch (_)` with one fixed
          // sentence, so an expired session and a timed-out request looked
          // identical to somebody who had just spoken a paragraph at their
          // phone and needed to know whether to try again.
          _error = brainDumpError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final insets = MediaQuery.of(context).viewInsets;

    return Padding(
      padding: EdgeInsets.only(bottom: insets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: AppSpacing.lg),
              decoration: BoxDecoration(
                color: c.text2.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // A mic, not a mascot. The orb that used to sit here was a
            // rendered marble with no relationship to the thing it was
            // doing: on a screen that says "listening" the one symbol
            // everybody already reads is a microphone, and the orb made
            // people wait to find out whether the app was recording. The
            // halo swells with your voice, so the page answers that in the
            // first syllable.
            SizedBox(
              height: 132,
              child: Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_phase == _Vp.listening) _LevelBloom(level: _level),
                    GlowRing(
                      size: 108,
                      icon: OmIcons.byName(_micIcon),
                      active:
                          _phase == _Vp.listening || _phase == _Vp.processing,
                      semanticLabel: _title,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(_title,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(_subtitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: c.text2, height: 1.4)),
            const SizedBox(height: AppSpacing.xl),
            _action(c),
          ],
        ),
      ),
    );
  }

  /// Mic while it is your turn, sparkles while the model has it. Leaving the
  /// mic up during processing said the app was still listening when it had
  /// already stopped.
  String get _micIcon => switch (_phase) {
        _Vp.processing => 'sparkles',
        _Vp.done => 'check',
        _Vp.error => 'mic-off',
        _ => 'mic',
      };

  String get _title => switch (_phase) {
        _Vp.listening => 'listening…',
        _Vp.empty => "didn't catch that",
        _Vp.processing => 'breaking it down…',
        _Vp.done => 'added $_added ${_added == 1 ? 'task' : 'tasks'}',
        _Vp.error => 'hmm',
      };

  String get _subtitle => switch (_phase) {
        _Vp.listening => _text.isEmpty
            ? 'talk as long as you like, tap done when you finish'
            : '“$_text”',
        _Vp.empty => 'tap to try again',
        _Vp.processing => '“$_text”',
        _Vp.done => "they're in today's backlog",
        _Vp.error => _error ?? 'something went wrong',
      };

  Widget _action(OmColors c) {
    switch (_phase) {
      case _Vp.listening:
        return _button(c, icon: 'check', label: 'done', onTap: _stopAndProcess);
      case _Vp.empty:
        return _button(c, icon: 'mic', label: 'try again', onTap: _start);
      case _Vp.error:
        // "Try again" is a dead end once the user has permanently refused the
        // mic - the system dialog will not come back, so tapping it just fails
        // again. Send them where the switch actually is.
        return _stt.micBlockedInSettings
            ? _button(c,
                icon: 'settings',
                label: 'open settings',
                onTap: _stt.openMicSettings)
            : _button(c, icon: 'mic', label: 'try again', onTap: _start);
      case _Vp.processing:
        return const SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        );
      case _Vp.done:
        return Icon(OmIcons.byName('check'), color: c.success, size: 30);
    }
  }

  Widget _button(OmColors c,
      {required String icon, required String label, required VoidCallback onTap}) {
    return OmTappable(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [c.primary, c.flow]),
          borderRadius: BorderRadius.circular(AppRadius.pill),
          boxShadow: [
            BoxShadow(
                color: c.primary.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(OmIcons.byName(icon), color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

/// The soft swell behind the mic, driven by how loud you actually are.
///
/// Sized rather than scaled, and drawn behind the button, so the tap target
/// never moves under a thumb that is still resting on it.
class _LevelBloom extends StatelessWidget {
  const _LevelBloom({required this.level});

  final double level;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final size = 104 + level * 46;
    return IgnorePointer(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              c.primary.withValues(alpha: 0.02),
              c.primary.withValues(alpha: 0.20 + level * 0.16),
              c.primary.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.72, 1.0],
          ),
        ),
      ),
    );
  }
}
