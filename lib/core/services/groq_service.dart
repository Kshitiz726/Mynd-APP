import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_config.dart';

/// All communication with the Groq REST API lives here.
///
/// Two modes:
///   [streamCompletion] - Server-Sent Events. Yields token chunks as they
///     arrive. Used for every live coaching turn so the UI feels immediate.
///   [complete]         - Plain blocking POST. Used for low-stakes internal
///     work like memory summarisation, where streaming adds no value.
class GroqService {
  GroqService._();
  static final GroqService instance = GroqService._();

  // ─── Config ───────────────────────────────────────────────────────────────

  // The key used to live here, supplied by `--dart-define=GROQ_API_KEY=...`.
  // That is not a way of keeping a secret: a dart-define is compiled into the
  // snapshot as a constant, and the key was recoverable with `strings` from any
  // installed build. There is no client-side fix for that, so the app no longer
  // holds a provider key at all - it calls our own server, which holds the key
  // and enforces the free-tier cap in the same place. See
  // server/src/routes/coach.ts.
  static Uri get _endpoint => ApiConfig.instance.rest('/api/coach/completions');

  /// Session auth, not a provider key.
  static Map<String, String> get _headers => {
        ...ApiConfig.instance.authHeaders,
        // Lets the server bucket the daily cap by the user's own midnight
        // rather than UTC's.
        'X-Timezone': DateTime.now().timeZoneName,
      };

  // Groq decommissioned the Llama chat models; llama-3.3-70b-versatile and
  // llama-3.1-8b-instant both answer 404 model_not_found, which surfaced in the
  // app as a thrown GroqException on every coaching turn. The gpt-oss pair is
  // what Groq now serves in that fast/large and fast/small shape.
  //
  // These are REASONING models, which matters here: they spend completion
  // tokens thinking before they answer, and that thinking comes out of the same
  // max_tokens budget. At the default effort a 512-token turn can be consumed
  // entirely by reasoning and return an EMPTY content string - a coach that
  // says nothing, with no error to explain it. _reasoningEffort pins that to
  // 'low' so the budget goes to the reply. Do not remove it without raising
  // the token ceilings to match.

  /// Primary model: fast, high-quality for live chat.
  static const _chatModel = 'openai/gpt-oss-120b';

  /// Lightweight model for summarisation (saves tokens).
  static const _summaryModel = 'openai/gpt-oss-20b';

  /// See the note above - this is what keeps a reply in the reply.
  static const _reasoningEffort = 'low';

  static const _chatMaxTokens = 512;
  static const _summaryMaxTokens = 300;

  final _client = http.Client();

  // ─── Streaming ────────────────────────────────────────────────────────────

  /// Streams token-by-token chunks from Groq.
  ///
  /// [messages] must already be fully assembled by [CoachPromptBuilder].
  /// Throws [GroqException] on non-200 responses.
  Stream<String> streamCompletion(
    List<Map<String, String>> messages,
  ) async* {
    final request = http.Request('POST', _endpoint);
    request.headers.addAll(_headers);
    request.body = jsonEncode({
      'model': _chatModel,
      'reasoning_effort': _reasoningEffort,
      'messages': messages,
      'temperature': 0.85,
      'top_p': 0.95,
      'max_tokens': _chatMaxTokens,
      'stream': true,
    });

    final response = await _client.send(request);

    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      // 402 is the daily free-tier cap, refused by the server rather than by
      // the composer. Given its own type so the UI can open the paywall instead
      // of showing a generic failure.
      if (response.statusCode == 402) {
        throw CoachLimitException(body);
      }
      throw GroqException(
        'Coach request failed (${response.statusCode}): $body',
        statusCode: response.statusCode,
      );
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (!line.startsWith('data: ')) continue;
      final payload = line.substring(6).trim();
      if (payload == '[DONE]') break;

      try {
        final json = jsonDecode(payload) as Map<String, dynamic>;
        final delta =
            (json['choices'] as List?)?.firstOrNull?['delta']
                as Map<String, dynamic>?;
        final chunk = delta?['content'] as String?;
        if (chunk != null && chunk.isNotEmpty) yield chunk;
      } catch (_) {
        // Malformed SSE chunk - skip silently.
      }
    }
  }

  // ─── Transcription (Whisper) ──────────────────────────────────────────────

  static Uri get _transcribeEndpoint =>
      ApiConfig.instance.rest('/api/coach/transcribe');

  /// Fast, cloud speech-to-text. Turbo Whisper is quick and cheap; it works on
  /// emulators (which have no on-device recogniser) as long as the mic captured
  /// real audio. Returns the transcript, or '' when nothing intelligible was
  /// heard.
  Future<String> transcribe(
    List<int> bytes, {
    String filename = 'audio.m4a',
    String model = 'whisper-large-v3-turbo',
  }) async {
    // Base64 in a JSON body rather than multipart: it is the transport the
    // avatar upload already uses, and it keeps the proxy route simple. The
    // server attaches the provider key and forwards it.
    final response = await _client.post(
      _transcribeEndpoint,
      headers: _headers,
      body: jsonEncode({
        'audio': base64Encode(bytes),
        'mime': 'audio/m4a',
        'model': model,
      }),
    );

    if (response.statusCode != 200) {
      throw GroqException(
        'Transcription failed (${response.statusCode}): ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final text = ((json['text'] ?? '') as String).trim();
    // Whisper fills silence with a handful of stock phrases lifted from its
    // training on captioned video. Treat those as "heard nothing".
    if (_isLikelySilence(text)) return '';
    return text;
  }

  static final _silenceFillers = <String>{
    'thank you', 'thank you.', 'thank you very much', 'thank you very much.',
    'thanks for watching', 'thanks for watching.', 'thanks for watching!',
    'thank you for watching', 'thank you for watching.', 'please subscribe',
    'you', 'bye', 'bye.', 'bye bye', '.', '..', '...',
  };

  static bool _isLikelySilence(String t) {
    final l = t.toLowerCase().trim();
    if (l.isEmpty) return true;
    return _silenceFillers.contains(l);
  }

  // ─── Blocking ─────────────────────────────────────────────────────────────

  /// Non-streaming completion - for summarisation and housekeeping tasks.
  Future<String> complete(List<Map<String, String>> messages) async {
    final response = await _client.post(
      _endpoint,
      headers: _headers,
      body: jsonEncode({
        'model': _summaryModel,
        'reasoning_effort': _reasoningEffort,
        'messages': messages,
        'temperature': 0.3, // low for factual summaries
        'max_tokens': _summaryMaxTokens,
        'stream': false,
      }),
    );

    if (response.statusCode != 200) {
      if (response.statusCode == 402) throw CoachLimitException(response.body);
      throw GroqException(
        'Coach request failed (${response.statusCode}): ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return json['choices'][0]['message']['content'] as String;
  }

  void dispose() => _client.close();
}

/// The server refused the turn because today's free-tier messages are spent.
///
/// Distinct from a generic failure so the UI can offer the paywall rather than
/// telling someone the coach is broken. The limit is now the server's - the
/// device counter it replaced could be reset by clearing app data.
class CoachLimitException implements Exception {
  const CoachLimitException(this.body);
  final String body;
  @override
  String toString() => 'CoachLimitException';
}

class GroqException implements Exception {
  const GroqException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'GroqException($statusCode): $message';
}
