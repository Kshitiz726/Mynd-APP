import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/puter_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../core/utils/om_icons.dart';
import '../../providers/coach_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_tappable.dart';

/// Hands-free "talk to Mynd" mode. Tap the orb to speak; it transcribes
/// (Puter speech2txt) → answers (Puter chat) → speaks back (Puter txt2speech).
/// The orb breathes and reacts to each phase; transitions are punctuated with
/// haptics. Text replies still live in the normal coach chat thread.
class CoachVoiceScreen extends StatefulWidget {
  const CoachVoiceScreen({super.key});

  @override
  State<CoachVoiceScreen> createState() => _CoachVoiceScreenState();
}

class _CoachVoiceScreenState extends State<CoachVoiceScreen> with TickerProviderStateMixin {
  final _puter = PuterService.instance;
  late final AnimationController _breathe;
  late final AnimationController _ripple;
  StreamSubscription<PuterVoiceState>? _sub;

  PuterVoiceState _state = PuterVoiceState.idle;
  String _userText = '';
  String _replyText = '';
  String? _status; // transient in-screen message (replaces SnackBar)
  bool _busy = false;
  bool _cancelled = false;
  
  int _highlightIndex = -1;
  Timer? _highlightTimer;

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _ripple = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    _sub = _puter.voiceState.listen((s) {
      if (!mounted) return;
      if (s != _state) _hapticFor(s);
      setState(() => _state = s);
    });
  }

  void _hapticFor(PuterVoiceState s) {
    switch (s) {
      case PuterVoiceState.listening:
        Haptics.medium();
      case PuterVoiceState.speaking:
        Haptics.light();
      case PuterVoiceState.idle:
        Haptics.light();
      default:
        break;
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _highlightTimer?.cancel();
    _breathe.dispose();
    _ripple.dispose();
    _puter.stopSpeaking();
    _puter.resetVoice();
    super.dispose();
  }

  void _onOrbDown() {
    if (_state == PuterVoiceState.idle && !_busy) {
      _startTurn();
    } else {
      _cancel(); // tap during other states cancels
    }
  }

  void _onOrbUp() {
    if (_state == PuterVoiceState.listening) {
      _finishTurn();
    }
  }

  void _cancel() {
    _cancelled = true;
    _highlightTimer?.cancel();
    _puter.stopSpeaking();
    _puter.resetVoice();
    if (mounted) {
      setState(() {
        _busy = false;
        _status = 'Cancelled — tap to talk';
      });
    }
  }

  void _resetBusy() {
    if (mounted) {
      setState(() => _busy = false);
    } else {
      _busy = false;
    }
  }

  Future<void> _startTurn() async {
    _cancelled = false;
    _highlightTimer?.cancel();
    setState(() {
      _userText = '';
      _replyText = '';
      _status = null;
      _highlightIndex = -1;
    });
    await _puter.startListening();
  }

  Future<void> _finishTurn() async {
    _busy = true;
    String text = '';
    try {
      text = await _puter.stopAndTranscribe();
    } catch (_) {/* falls through to empty-text handling */}
    if (!mounted || _cancelled) return _resetBusy();

    if (text.trim().isEmpty) {
      _puter.resetVoice();
      setState(() => _status = "Didn't catch that — tap to try again");
      return _resetBusy();
    }

    setState(() {
      _userText = text;
      _status = null;
    });
    _puter.emitThinking();
    try {
      final reply = await context
          .read<CoachProvider>()
          .sendAndAwaitReply(text)
          .timeout(const Duration(seconds: 45), onTimeout: () => '');
      if (!mounted || _cancelled) return _resetBusy();
      if (reply.trim().isEmpty) {
        _puter.resetVoice();
        setState(() => _status = 'Mynd had trouble replying — tap to retry');
        return _resetBusy();
      }
      setState(() => _replyText = reply);
      _startHighlighting(reply);
      await _puter.speak(reply);
    } catch (_) {
      _puter.resetVoice();
      if (mounted) setState(() => _status = 'Something went wrong — tap to retry');
    } finally {
      _resetBusy();
    }
  }

  void _startHighlighting(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    _highlightIndex = 0;
    _highlightTimer?.cancel();
    _highlightTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_highlightIndex < words) {
          _highlightIndex++;
        } else {
          timer.cancel();
        }
      });
    });
  }

  String get _statusLabel => switch (_state) {
        PuterVoiceState.idle => 'Hold to talk',
        PuterVoiceState.listening => 'Listening…',
        PuterVoiceState.transcribing => 'Got it…',
        PuterVoiceState.thinking => 'Thinking…',
        PuterVoiceState.speaking => 'Speaking…',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final isDark = context.isDark;
    final orbColor = switch (_state) {
      PuterVoiceState.listening => c.primary,
      PuterVoiceState.thinking || PuterVoiceState.transcribing => c.accent,
      PuterVoiceState.speaking => c.flow,
      PuterVoiceState.idle => c.primary,
    };

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0E0E14) : c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 16, 0),
              child: Row(
                children: [
                  OmTappable(
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(OmIcons.byName('chevL'), color: c.text),
                    ),
                  ),
                  const Spacer(),
                  Text('Talk with Mynd',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.text2)),
                  const Spacer(),
                  OmAvatar(
                    userId: 'me',
                    fallbackInitial: '?',
                    fallbackColor: c.primary,
                    size: 36,
                  ),
                ],
              ),
            ),

            // Captions
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_userText.isNotEmpty)
                      Text('“$_userText”',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.text2)),
                    if (_replyText.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Flexible(
                        child: SingleChildScrollView(
                          child: _HighlightedText(text: _replyText, highlightIndex: _highlightIndex),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // The orb
            Listener(
              onPointerDown: (_) => _onOrbDown(),
              onPointerUp: (_) => _onOrbUp(),
              onPointerCancel: (_) => _onOrbUp(),
              child: AnimatedBuilder(
                animation: Listenable.merge([_breathe, _ripple]),
                builder: (context, _) {
                  final active = _state != PuterVoiceState.idle;
                  final breathe = 0.5 + 0.5 * _breathe.value;
                  final baseScale = 1.0 + (active ? 0.06 : 0.03) * math.sin(breathe * math.pi);
                  return SizedBox(
                    width: 240,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Expanding ripples while listening/speaking
                        if (_state == PuterVoiceState.listening || _state == PuterVoiceState.speaking)
                          ...List.generate(2, (i) {
                            final t = (_ripple.value + i / 2) % 1.0;
                            return Container(
                              width: 150 + t * 110,
                              height: 150 + t * 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: orbColor.withValues(alpha: (1 - t) * 0.35)),
                              ),
                            );
                          }),
                        // Core orb
                        Transform.scale(
                          scale: baseScale,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [orbColor, Color.lerp(orbColor, c.accent, 0.5)!],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: orbColor.withValues(alpha: 0.45),
                                  blurRadius: 40,
                                  spreadRadius: active ? 8 : 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              _state == PuterVoiceState.speaking
                                  ? Icons.graphic_eq_rounded
                                  : (_state == PuterVoiceState.thinking ||
                                          _state == PuterVoiceState.transcribing)
                                      ? Icons.more_horiz_rounded
                                      : Icons.mic_rounded,
                              color: Colors.white,
                              size: 48,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Text(_status ?? _statusLabel,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: c.text, fontWeight: FontWeight.w600)),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }
}

class _HighlightedText extends StatelessWidget {
  const _HighlightedText({required this.text, required this.highlightIndex});
  final String text;
  final int highlightIndex;

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final words = text.split(RegExp(r'\s+'));
    final matches = RegExp(r'\s+').allMatches(text).toList();

    final spans = <TextSpan>[];
    for (int i = 0; i < words.length; i++) {
      if (words[i].isEmpty) continue;
      spans.add(
        TextSpan(
          text: words[i],
          style: TextStyle(
            color: highlightIndex >= i ? c.text : c.text2.withValues(alpha: 0.4),
          ),
        ),
      );
      if (i < matches.length) {
        spans.add(TextSpan(text: matches[i].group(0)));
      }
    }

    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: Theme.of(context).textTheme.titleMedium?.copyWith(color: c.text, height: 1.4),
        children: spans,
      ),
    );
  }
}
