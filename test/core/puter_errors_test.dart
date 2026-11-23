import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/ai/chat_backend.dart';
import 'package:ourmynd/core/services/ai/puter_backend.dart';
import 'package:ourmynd/core/services/puter_service.dart';

/// "Claude and Gemini are connected but the chat won't work."
///
/// The cause was not the code at all: the Puter account had run out of
/// credits, and Puter said so plainly. The app's part of the fault was that it
/// never passed that on. A PuterException is not a ChatBackendException, so it
/// fell past the coach's provider-error branch into a generic "that didn't go
/// through", and the one sentence that told the user what to do was dropped.
void main() {
  test('not being signed in says so, rather than timing out', () async {
    // The bridge would otherwise sit for forty seconds before reporting
    // anything, which reads as the app being broken.
    expect(PuterService.instance.signedIn, isFalse,
        reason: 'no bridge under flutter test, so this is the signed-out path');

    const backend = PuterBackend(AiProvider.claude);
    await expectLater(
      backend.streamCompletion(const [
        {'role': 'user', 'content': 'hello'},
      ]),
      emitsError(isA<ChatBackendException>()
          .having((e) => e.needsSignIn, 'needsSignIn', isTrue)
          .having((e) => e.message, 'message', contains('Claude Opus'))),
    );
  });

  test('the message names the provider the user actually chose', () async {
    // Gemini and Claude are the same code path with a different id, so an
    // error that always said "Claude" would be wrong half the time.
    const backend = PuterBackend(AiProvider.gemini);
    await expectLater(
      backend.streamCompletion(const [
        {'role': 'user', 'content': 'hello'},
      ]),
      emitsError(isA<ChatBackendException>()
          .having((e) => e.message, 'message', contains('Gemini Flash'))),
    );
  });
}
