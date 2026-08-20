import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/puter_service.dart';
import '../../core/services/speech_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/utils/haptics.dart';
import '../../providers/coach_provider.dart';
import '../../widgets/om_avatar.dart';
import '../../widgets/om_back_button.dart';

/// Hands-free "talk to Mynd", the way ChatGPT voice works.
///
/// Tap once to start; it listens, and when you pause it transcribes on-device
/// (recorded in the Puter bridge → Groq Whisper), answers through the same Puter
/// chat the typed coach uses, speaks the reply back (Puter neural `txt2speech`),
/// and then listens again on its own. No button between turns. Tap the orb any
/// time to stop. The orb breathes, ripples, and swells with your voice; each
/// phase is punctuated with haptics; the text of every turn also lands in the
/// normal coach thread.
class CoachVoiceScreen extends StatefulWidget {
  const CoachVoiceScreen({super.key});

  @override
  State<CoachVoiceScreen> createState() => _CoachVoiceScreenState();
}

/// Where the turn is: waiting, hearing you out, thinking, or talking back.
enum _Phase { idle, listening, thinking, speaking }

class _CoachVoiceScreenState extends State<CoachVoiceScreen>
    with TickerProviderStateMixin {
  final _stt = SpeechService.instance;
  final _puter = PuterService.instance;

  late final AnimationController _breathe;
  late final AnimationController _ripple;

  /// True while the conversation is running (across many turns). Tapping the orb
  /// toggles it; leaving the screen ends it.
  bool _active = false;

  _Phase _phase = _Phase.idle;
  String _userText = '';
  String _replyText = '';
  String? _status;
  double _level = 0;

  // Voice-activity detection.
  bool _sawSpeech = false;
  bool _turnEnding = false;
  DateTime _lastLoud = DateTime.now();
  DateTime _turnStart = DateTime.now();
  int _emptyStreak = 0;

  int _highlightIndex = -1;
  Timer? _highlightTimer;

  // A pause this long after speech ends the turn; this long of pure silence
  // with nothing said gives up; and no turn runs longer than the cap.
  static const _speechThresh = 0.06;
  static const _silenceHold = Duration(milliseconds: 1200);
  static const _noSpeechTimeout = Duration(seconds: 9);
  static const _maxTurn = Duration(seconds: 30);

  @override
  void initState() {
    super.initState();
    _breathe = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2400))
      ..repeat(reverse: true);
    _ripple = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat();
    // Start listening straight away, so opening the screen is the only tap.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _active = true;
        _listen();
      }
    });
  }

  @override
  void dispose() {
    _active = false;
    _highlightTimer?.cancel();
    _breathe.dispose();
    _ripple.dispose();
    _stt.cancel();
    _puter.stopSpeaking();
    _puter.resetVoice();
    super.dispose();
  }

  void _onTap() {
    if (_active) {
      _stopConversation();
    } else {
      _active = true;
      _emptyStreak = 0;
      _listen();
    }
  }

  void _stopConversation() {
    _active = false;
    _turnEnding = true;
    _highlightTimer?.cancel();
    _stt.cancel();
    _puter.stopSpeaking();
    if (mounted) {
      setState(() {
        _phase = _Phase.idle;
        _status = 'Tap to talk';
        _level = 0;
      });
    }
  }

  Future<void> _listen() async {
    if (!_active || !mounted) return;
    _turnEnding = false;
    _sawSpeech = false;
    _lastLoud = DateTime.now();
    _turnStart = DateTime.now();
    setState(() {
      _phase = _Phase.listening;
      _userText = '';
      _replyText = '';
      _status = null;
      _level = 0;
    });
    final ok = await _stt.startRecording(onLevel: _onLevel);
    if (!ok && mounted) {
      _active = false;
      setState(() {
        _phase = _Phase.idle;
        _status = _stt.lastError ?? 'Microphone unavailable.';
      });
    }
  }

  void _onLevel(double l) {
    if (!mounted || _phase != _Phase.listening) return;
    setState(() => _level = _level * 0.6 + l * 0.4);
    final now = DateTime.now();
    if (l > _speechThresh) {
      _sawSpeech = true;
      _lastLoud = now;
    }
    final sinceLoud = now.difference(_lastLoud);
    final sinceStart = now.difference(_turnStart);
    if (_sawSpeech && sinceLoud > _silenceHold) {
      _endTurn();
    } else if (!_sawSpeech && sinceStart > _noSpeechTimeout) {
      _endTurn(noSpeech: true);
    } else if (sinceStart > _maxTurn) {
      _endTurn();
    }
  }

  Future<void> _endTurn({bool noSpeech = false}) async {
    if (_turnEnding) return;
    _turnEnding = true;

    if (noSpeech) {
      await _stt.cancel();
      _active = false;
      if (mounted) {
        setState(() {
          _phase = _Phase.idle;
          _status = "I didn't hear anything. Tap the orb and speak.";
        });
      }
      return;
    }

    setState(() {
      _phase = _Phase.thinking;
      _status = 'transcribing…';
      _level = 0;
    });
    final text = await _stt.stopAndTranscribe();
    if (!mounted || !_active) return;
    await _handle(text);
  }

  Future<void> _handle(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) {
      _emptyStreak++;
      if (_emptyStreak >= 2) {
        _active = false;
        if (mounted) {
          setState(() {
            _phase = _Phase.idle;
            _status = "I couldn't make that out. Tap to try again.";
          });
        }
        return;
      }
      _listen(); // give it one more go without making them tap
      return;
    }
    _emptyStreak = 0;

    setState(() {
      _userText = clean;
      _phase = _Phase.thinking;
      _status = null;
    });
    Haptics.light();

    String reply = '';
    try {
      reply = await context
          .read<CoachProvider>()
          .sendAndAwaitReply(clean)
          .timeout(const Duration(seconds: 45), onTimeout: () => '');
    } catch (_) {/* fall through to resume */}
    if (!mounted || !_active) return;

    if (reply.trim().isEmpty) {
      _listen();
      return;
    }
    setState(() {
      _replyText = reply;
      _phase = _Phase.speaking;
    });
    _startHighlighting(reply);
    await _puter.speak(reply);
    _highlightTimer?.cancel();
    if (!mounted || !_active) return;
    _listen(); // hands-free: straight back to listening
  }

  void _startHighlighting(String text) {
    final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    _highlightIndex = 0;
    _highlightTimer?.cancel();
    _highlightTimer =
        Timer.periodic(const Duration(milliseconds: 300), (timer) {
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

  String get _statusLabel => switch (_phase) {
        _Phase.idle => 'Tap to talk',
        _Phase.listening => 'Listening…',
        _Phase.thinking => 'Thinking…',
        _Phase.speaking => 'Speaking…',
      };

  @override
  Widget build(BuildContext context) {
    final c = context.omColors;
    final isDark = context.isDark;
    final orbColor = switch (_phase) {
      _Phase.listening => c.primary,
      _Phase.thinking => c.accent,
      _Phase.speaking => c.flow,
      _Phase.idle => c.primary,
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
                  OmBackButton(onTap: () => Navigator.of(context).maybePop()),
                  const Spacer(),
                  Text('Talk with Mynd',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(color: c.text2)),
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
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: c.text2)),
                    if (_replyText.isNotEmpty) ...[
                      const SizedBox(height: 18),
                      Flexible(
                        child: SingleChildScrollView(
                          child: _HighlightedText(
                              text: _replyText,
                              highlightIndex: _highlightIndex),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // The orb
            GestureDetector(
              onTap: _onTap,
              behavior: HitTestBehavior.opaque,
              child: AnimatedBuilder(
                animation: Listenable.merge([_breathe, _ripple]),
                builder: (context, _) {
                  final active = _phase != _Phase.idle;
                  final breathe = 0.5 + 0.5 * _breathe.value;
                  final baseScale = 1.0 +
                      (active ? 0.06 : 0.03) * math.sin(breathe * math.pi) +
                      (_phase == _Phase.listening ? _level * 0.16 : 0.0);
                  return SizedBox(
                    width: 240,
                    height: 240,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (_phase == _Phase.listening ||
                            _phase == _Phase.speaking)
                          ...List.generate(2, (i) {
                            final t = (_ripple.value + i / 2) % 1.0;
                            return Container(
                              width: 150 + t * 110,
                              height: 150 + t * 110,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: orbColor.withValues(
                                        alpha: (1 - t) * 0.35)),
                              ),
                            );
                          }),
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
                                colors: [
                                  orbColor,
                                  Color.lerp(orbColor, c.accent, 0.5)!
                                ],
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
                              switch (_phase) {
                                _Phase.speaking => Icons.graphic_eq_rounded,
                                _Phase.thinking => Icons.more_horiz_rounded,
                                _Phase.listening => Icons.mic_rounded,
                                _Phase.idle => Icons.mic_none_rounded,
                              },
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
            const SizedBox(height: 6),
            Text(_active ? 'tap the orb to stop' : 'tap the orb to start',
                textAlign: TextAlign.center,
                style:
                    Theme.of(context).textTheme.bodySmall?.copyWith(color: c.text2)),
            const SizedBox(height: 24),
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
            color:
                highlightIndex >= i ? c.text : c.text2.withValues(alpha: 0.4),
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
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(color: c.text, height: 1.4),
        children: spans,
      ),
    );
  }
}
