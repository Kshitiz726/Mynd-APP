import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'api_client.dart';
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

  /// How much the model is allowed to think before it answers.
  ///
  /// Was 'low', paired with a 1024-token ceiling, and that pairing was the
  /// single biggest cause of flat, going-through-the-motions replies: a
  /// reasoning model told not to reason answers from the surface of the
  /// prompt. The therapeutic stance the system prompt now asks for is exactly
  /// the kind of instruction that needs thinking to follow, because getting
  /// the meaning underneath what somebody said is not a surface operation.
  ///
  /// Raised to 'medium' together with [_chatMaxTokens], which is the condition
  /// the note above sets: the thinking comes out of the same budget, so the
  /// budget had to grow first or replies come back empty. Do not raise one of
  /// these without the other.
  static const _reasoningEffort = 'medium';

  // Raised from 512, and not for longer replies.
  //
  // These models spend completion tokens thinking before they answer, out of
  // this same budget. At 512 a turn could be consumed entirely by reasoning
  // and come back with an EMPTY content string: a coach that says nothing,
  // with no error to explain it. The system prompt grew when the agent
  // personas and the email instructions landed, which pushed ordinary turns
  // into that margin. The replies are still capped by the prompt telling the
  // agent how long to be, not by this number.
  // Raised again, from 1024, when _reasoningEffort went to 'medium'. Thinking
  // and reply share this budget, so a medium-effort turn needs headroom the
  // 1024 did not leave. Reply length is still governed by the prompt, not by
  // this number: what the extra room buys is a better-considered reply, not a
  // longer one.
  static const _chatMaxTokens = 3072;
  static const _summaryMaxTokens = 300;

  final _client = http.Client();


  /// Send, and if the session had just expired, refresh once and send again.
  ///
  /// Access tokens last thirty minutes, so a 401 here is the ordinary end of a
  /// token's life rather than a sign that anything is wrong. [ApiClient] has
  /// always handled that by refreshing and replaying; this service did not,
  /// because it has its own http.Client and never went through that path. The
  /// result was a split personality: open the app after half an hour and the
  /// feed, the rooms and the profile all quietly refreshed and worked, while
  /// Brain Dump, the voice capture, the goal planner and the motivation card
  /// answered "your session expired" to somebody whose session was fine.
  ///
  /// [send] is a closure rather than a prepared request because it has to run
  /// twice, picking up the NEW auth header the second time.
  Future<http.Response> _withRefresh(
    Future<http.Response> Function() send,
  ) async {
    final res = await send();
    if (res.statusCode != 401) return res;
    if (!await ApiClient.instance.refreshSession()) return res;
    return send();
  }

  // ─── Streaming ────────────────────────────────────────────────────────────

  /// Streams token-by-token chunks from Groq.
  ///
  /// [messages] must already be fully assembled by [CoachPromptBuilder].
  /// Throws [GroqException] on non-200 responses.
  Stream<String> streamCompletion(
    List<Map<String, String>> messages,
  ) async* {
    // Built per attempt rather than once: a Request cannot be sent twice, and
    // the retry has to pick up the refreshed auth header anyway.
    http.Request build() => http.Request('POST', _endpoint)
      ..headers.addAll(_headers)
      ..body = jsonEncode({
        'model': _chatModel,
        'reasoning_effort': _reasoningEffort,
        'messages': messages,
        'temperature': 0.85,
        'top_p': 0.95,
        'max_tokens': _chatMaxTokens,
        'stream': true,
      });

    var response = await _client.send(build());
    // Same expired-token replay as every other call here. Draining the stream
    // first because a 401 body is small and the connection has to be finished
    // with before the retry goes out.
    if (response.statusCode == 401) {
      await response.stream.drain<void>();
      if (await ApiClient.instance.refreshSession()) {
        response = await _client.send(build());
      }
    }

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
    final response = await _withRefresh(
      () => _client.post(
        _transcribeEndpoint,
        headers: _headers,
        body: jsonEncode({
          'audio': base64Encode(bytes),
          'mime': 'audio/m4a',
          'model': model,
        }),
      ),
    )
        // Generous, because this uploads the whole clip, but bounded: without
        // it the voice sheet sits on "breaking it down" with nothing left to
        // move it on.
        .timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw const GroqException(
        'Transcription timed out',
        statusCode: 408,
      ),
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

  // ─── Motivation ───────────────────────────────────────────────────────────

  static Uri get _motivationEndpoint =>
      ApiConfig.instance.rest('/api/coach/motivation');

  /// The day's motivation lines, written fresh.
  ///
  /// Its own endpoint, not [complete], because [complete] spends a coaching
  /// turn: motivation was quietly eating the five free daily messages, so two
  /// mood changes left the coach refusing to talk and the lines silently
  /// falling back to the small written bank. The visible symptom was an app
  /// that seemed to ignore the mood.
  ///
  /// [temperature] runs hot on purpose. These are one-line sentences with no
  /// facts to get wrong, and the failure people actually notice is reading the
  /// same encouragement for the third time this week.
  ///
  /// Throws [MotivationLimitException] when the day's allowance is spent, which
  /// the caller treats as "use the bank" rather than as an error worth showing.
  Future<String> motivation(
    List<Map<String, String>> messages, {
    double temperature = 1.05,
  }) async {
    // Bounded, because the caller shows a loading state for exactly as long as
    // this takes. An unbounded request makes that a loading state with no end:
    // the model call reached the server, the server's own upstream call never
    // came back, and the card sat on its skeleton for as long as the app was
    // open. Failing here is recoverable - the caller falls back to the local
    // bank and shows words. Hanging here is not.
    final response = await _withRefresh(
      () => _client.post(
        _motivationEndpoint,
        headers: _headers,
        body: jsonEncode({'messages': messages, 'temperature': temperature}),
      ),
    )
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw const GroqException(
            'Motivation request timed out',
            statusCode: 408,
          ),
        );

    if (response.statusCode == 429) {
      throw MotivationLimitException(response.body);
    }
    if (response.statusCode != 200) {
      throw GroqException(
        'Motivation request failed (${response.statusCode}): ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    final message = choices?.firstOrNull?['message'] as Map<String, dynamic>?;
    return ((message?['content'] ?? '') as String).trim();
  }

  // ─── Blocking ─────────────────────────────────────────────────────────────

  /// Non-streaming completion - for summarisation and housekeeping tasks.
  /// Turn what the user typed or spoke into structured JSON.
  ///
  /// Its own endpoint rather than [complete], because that one is the metered
  /// coach route: emptying your head into the app was spending one of the five
  /// free coaching messages a day, and once they were gone Brain Dump failed
  /// with a message about a chat limit. The server does not count this one, and
  /// it picks the model and the ceiling itself.
  ///
  /// [task] selects the token ceiling on the server and nothing else. A goal
  /// plan needs far more room than a list of task titles, and asking for it
  /// under the extraction ceiling truncates the JSON mid-array - which arrives
  /// as a parse failure rather than as a short plan.
  Future<String> extract(
    List<Map<String, String>> messages, {
    String task = 'extract',
  }) async {
    final response = await _withRefresh(
      () => _client.post(
        ApiConfig.instance.rest('/api/coach/extract'),
        headers: _headers,
        body: jsonEncode({'task': task, 'messages': messages}),
      ),
    )
        .timeout(
      const Duration(seconds: 60),
      onTimeout: () => throw const GroqException(
        'Reading that took too long',
        statusCode: 408,
      ),
    );

    if (response.statusCode != 200) {
      throw GroqException(
        'Could not read that (${response.statusCode}): ${response.body}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    final choices = json['choices'] as List?;
    final message = choices?.firstOrNull?['message'] as Map<String, dynamic>?;
    final content = ((message?['content'] ?? '') as String).trim();

    // An empty answer is a real, silent failure mode here, not a defensive
    // nicety. These are reasoning models: the thinking is spent out of the same
    // token budget as the reply, so a ceiling that is too low returns HTTP 200
    // with content: "". That reached the caller as jsonDecode('') and surfaced
    // as a FormatException - a parse error blamed on the user's words, when
    // nothing was wrong with them and nothing had been written at all.
    if (content.isEmpty) {
      throw const GroqException(
        'The model returned nothing',
        statusCode: 502,
      );
    }
    return content;
  }

  /// The metered coach route. Nothing in the app calls this today, and that is
  /// deliberate rather than an oversight: the live conversation runs on Puter,
  /// so everything that ever reached here was the app's own plumbing - reading
  /// a brain dump, planning a goal, guessing a mood, rewriting the memory - and
  /// the five-a-day cap was rationing housekeeping instead of chat. Anything
  /// that is not a person talking to the coach belongs on [extract].
  Future<String> complete(List<Map<String, String>> messages) async {
    final response = await _withRefresh(
      () => _client.post(
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
      ),
    )
        // A request with no bound is a UI that can hang forever. This one held
        // the memory refresh open, and the refresh held Home's busy flag, so a
        // single stalled POST left the reload button and the mic dead until the
        // app was killed. A summary that has not arrived in 45 seconds is not
        // coming.
        .timeout(
      const Duration(seconds: 45),
      onTimeout: () => throw const GroqException(
        'Coach request timed out',
        statusCode: 408,
      ),
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

/// The day's motivation allowance is spent.
///
/// Separate from [CoachLimitException] because the consequence is different:
/// running out of coaching turns opens the paywall, running out of motivation
/// lines just means today's come from the written bank and nobody is told.
class MotivationLimitException implements Exception {
  const MotivationLimitException(this.body);
  final String body;
  @override
  String toString() => 'MotivationLimitException';
}

class GroqException implements Exception {
  const GroqException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'GroqException($statusCode): $message';
}
