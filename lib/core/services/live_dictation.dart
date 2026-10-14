import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';

/// Dictation that appears as you speak.
///
/// The app already had a voice path: the bridge WebView opened a MediaRecorder,
/// kept the whole clip, and posted it to a transcriber when you stopped. That
/// has two problems and this replaces it for typing.
///
/// The first is that you learn nothing until you stop. You talk at a screen
/// that shows no words, and if the capture produced nothing you find out at the
/// end, by which point the sentence is gone and all the app can say is "didn't
/// catch that" - which is what it kept saying.
///
/// The second is that the capture happened inside a zero-size, off-screen
/// WebView. Browsers suspend audio in a view like that, so on a simulator, and
/// on some real devices, the recorder produced a clip too small to be speech
/// and the whole thing failed silently every time.
///
/// This uses the platform's own recogniser instead - SFSpeechRecognizer on iOS,
/// SpeechRecognizer on Android. It reports partial results while you are still
/// talking, which is the live transcript, and it needs no network round trip
/// per sentence.
class LiveDictation {
  LiveDictation._();
  static final LiveDictation instance = LiveDictation._();

  final stt.SpeechToText _speech = stt.SpeechToText();

  bool _ready = false;
  bool _listening = false;
  bool get isListening => _listening;

  /// Why the last attempt failed, in words that name the actual problem.
  String? lastError;

  /// True when the refusal was permanent, so the caller can offer Settings
  /// rather than suggesting another go at a dialog that will not reappear.
  bool blockedInSettings = false;

  /// Kept under the name the voice sheet already used, so both callers ask the
  /// same question of the same object.
  bool get micBlockedInSettings => blockedInSettings;

  /// Open this app's page in the OS settings, for a permanent refusal.
  Future<void> openMicSettings() => openAppSettings();

  /// Ask the platform for the recogniser and the permissions it needs.
  ///
  /// Safe to call repeatedly: the plugin returns the first answer after that.
  Future<bool> prepare() async {
    lastError = null;
    blockedInSettings = false;
    try {
      _ready = await _speech.initialize(
        onStatus: (s) {
          // 'done' and 'notListening' both mean the session has ended - the OS
          // stops on its own after a pause, so this is the only honest source
          // of "are we still listening".
          if (s == 'done' || s == 'notListening') _listening = false;
        },
        onError: (SpeechRecognitionError e) {
          debugPrint('[dictation] ${e.errorMsg} permanent=${e.permanent}');
          _listening = false;
          lastError = explain(e.errorMsg);
          blockedInSettings = e.permanent && _isPermission(e.errorMsg);
        },
      );
      if (!_ready) {
        lastError ??= 'Speech recognition is not available on this device.';
      }
      return _ready;
    } catch (e) {
      debugPrint('[dictation] initialize threw: $e');
      lastError = 'Speech recognition could not start. $e';
      return false;
    }
  }

  /// Start listening. [onText] fires repeatedly with the transcript so far.
  ///
  /// [onText] receives every partial result, so the caller can show the words
  /// appearing. The second argument says whether the recogniser considers that
  /// text final.
  Future<bool> start({
    required void Function(String text, bool isFinal) onText,
    void Function(double level)? onLevel,
  }) async {
    if (_listening) return true;
    if (!_ready && !await prepare()) return false;

    try {
      await _speech.listen(
        onResult: (r) => onText(r.recognizedWords, r.finalResult),
        onSoundLevelChange: onLevel == null
            ? null
            // Normalised here rather than at the call site: iOS reports
            // decibels around -2..10 and Android a 0..10 scale, and a button
            // that swells should not have to know which platform it is on.
            : (l) => onLevel(((l + 2) / 12).clamp(0.0, 1.0)),
        listenOptions: stt.SpeechListenOptions(
          partialResults: true,
          // A long sentence must not be cut off mid-thought, and a pause for
          // breath is not the end of a message.
          listenFor: const Duration(minutes: 2),
          pauseFor: const Duration(seconds: 6),
          // Dictation, not a voice command: it is a sentence, not one word.
          listenMode: stt.ListenMode.dictation,
          cancelOnError: false,
          // Network recognition is allowed. Forcing on-device would refuse to
          // start wherever the offline model is not installed, which is most
          // phones, and the failure looks identical to a broken microphone.
          onDevice: false,
        ),
      );
      _listening = true;
      return true;
    } catch (e) {
      debugPrint('[dictation] listen threw: $e');
      lastError = 'Could not start listening. $e';
      return false;
    }
  }

  /// Stop and keep what was heard.
  Future<void> stop() async {
    if (!_listening) return;
    _listening = false;
    try {
      await _speech.stop();
    } catch (e) {
      debugPrint('[dictation] stop threw: $e');
    }
  }

  /// Stop and throw it away.
  Future<void> cancel() async {
    if (!_listening) return;
    _listening = false;
    try {
      await _speech.cancel();
    } catch (e) {
      debugPrint('[dictation] cancel threw: $e');
    }
  }

  static bool _isPermission(String code) =>
      code.contains('permission') || code.contains('denied');

  /// The plugin's error codes are not sentences. These are.
  ///
  /// Worth the mapping: "error_speech_timeout" on screen tells somebody
  /// nothing, and the cases below need different things from them. Public so a
  /// test can check the wording without a microphone.
  @visibleForTesting
  static String explain(String code) {
    if (_isPermission(code)) {
      return 'OurMynd needs the microphone and speech recognition to hear you. '
          'You can switch them on in Settings.';
    }
    if (code.contains('no_match') || code.contains('speech_timeout')) {
      return "Didn't catch anything that time.";
    }
    if (code.contains('network')) {
      return 'Speech recognition needs a connection and could not reach it.';
    }
    if (code.contains('busy')) {
      return 'The microphone is busy. Close anything else using it and try '
          'again.';
    }
    return 'Dictation stopped unexpectedly. Try again?';
  }
}
