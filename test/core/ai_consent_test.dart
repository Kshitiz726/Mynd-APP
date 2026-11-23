import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ourmynd/providers/ai_consent_provider.dart';

/// The gate that decides whether a user's words may be sent to the third-party
/// AI provider. Its two failure directions are opposite and both matter, so
/// they are pinned here rather than left to a reading of the provider.
///
///   * Processing fails CLOSED: until an answer is positively known, nothing is
///     sent. A bug that defaulted this to "yes" would send data to a third
///     party without agreement, which is the whole violation.
///   * Asking fails OPEN: the disclosure is only forced once the server has
///     confirmed there is no answer on file, never on the strength of a cache
///     we could not fill. A bug the other way turns an unreachable server into
///     a coach that is permanently stuck on a screen it cannot get past.
void main() {
  final ai = AiConsentProvider.instance;

  // The provider is a singleton, so each test starts from a cleared one rather
  // than inheriting the last test's answer.
  tearDown(() async {
    SharedPreferences.setMockInitialValues({});
    await ai.clear();
  });

  test('fails closed before anything is known', () async {
    SharedPreferences.setMockInitialValues({});
    await ai.clear();
    expect(ai.granted, isFalse, reason: 'nothing may be sent on an unknown answer');
    expect(ai.needsDecision, isTrue);
  });

  test('a cached yes grants, a cached no declines', () async {
    SharedPreferences.setMockInitialValues({'om_ai_consent_granted': true});
    await ai.loadCached();
    expect(ai.granted, isTrue);
    expect(ai.declined, isFalse);

    // loadCached fully replaces the in-memory answer from prefs, so there is no
    // need to clear between the two reads - and clearing would wipe the mock
    // values this very test just set.
    SharedPreferences.setMockInitialValues({'om_ai_consent_granted': false});
    await ai.loadCached();
    expect(ai.granted, isFalse);
    expect(ai.declined, isTrue, reason: 'a settled no is distinct from unanswered');
    expect(ai.needsDecision, isFalse);
  });

  test('an absent answer is a third state, not a no', () async {
    SharedPreferences.setMockInitialValues({});
    await ai.loadCached();
    expect(ai.declined, isFalse, reason: 'never-asked must not read as declined');
    expect(ai.needsDecision, isTrue);
  });

  test('the disclosure is shown without waiting for the server', () async {
    // This replaces a test that asserted the opposite, and the reversal is the
    // point rather than a relaxation.
    //
    // mustAsk used to also require the server to confirm there was no answer
    // on file, so that nobody was shown a question whose answer could not be
    // recorded. That held while the answer was recorded by POST and nothing
    // else. It does not now: grant and withdraw write to the device first and
    // sync afterwards.
    //
    // What the old rule did in practice, with /consent/ai returning 404 on
    // both servers, was hold mustAsk permanently false - so the disclosure was
    // never shown and the chat sent messages to a third-party AI provider
    // without anyone being asked. Guideline 5.1.2(i) requires permission
    // before that data moves, so failing open on the *asking* was the one
    // behaviour that could not be defended.
    SharedPreferences.setMockInitialValues({});
    await ai.loadCached();
    expect(ai.needsDecision, isTrue);
    expect(ai.mustAsk, isTrue,
        reason: 'nothing may be sent to the provider before this is answered');
  });

  test('nothing is asked before the stored answer has been read', () async {
    // The other half of the rule. Without the loaded guard a cold start would
    // show the disclosure for a frame to somebody who agreed months ago.
    SharedPreferences.setMockInitialValues({'om_ai_consent_granted': true});
    await ai.loadCached();
    expect(ai.mustAsk, isFalse, reason: 'they have already answered');
  });

  test('clear forgets the answer when the account changes', () async {
    SharedPreferences.setMockInitialValues({'om_ai_consent_granted': true});
    await ai.loadCached();
    expect(ai.granted, isTrue);
    await ai.clear();
    expect(ai.granted, isFalse);
    expect(ai.needsDecision, isTrue, reason: 'the next account inherits no decision');
  });

  test('an unconfirmed answer is not a refusal', () async {
    // The bug this pins: the coach screen fails OPEN when the answer cannot be
    // established (offline, or a server predating the endpoint), so the chat
    // opens. If the send path then failed CLOSED on !granted, the user would
    // get a chat that rejects every message they type. `declined` is the only
    // thing that may block a send, and an unknown answer is not declined.
    SharedPreferences.setMockInitialValues({});
    await ai.loadCached();
    expect(ai.granted, isFalse, reason: 'still nothing may be sent speculatively');
    expect(ai.declined, isFalse, reason: 'and nothing may be treated as a refusal');
  });

  group('agreement is to a named recipient', () {
    // 5.1.2(i) asks the app to specify who the data is sent to. That makes the
    // recipient part of what was agreed, not a detail around it: somebody who
    // said yes while the built-in model was answering has not agreed to their
    // words going to Anthropic through Puter.

    test('the recorded answer remembers who it was about', () async {
      SharedPreferences.setMockInitialValues({});
      await ai.clear();
      await ai.grant(source: 'connect', company: 'Groq');

      expect(ai.consentedCompany, 'Groq');
    });

    test('a different recipient needs asking again', () async {
      SharedPreferences.setMockInitialValues({});
      await ai.clear();
      await ai.grant(source: 'coach', company: 'Groq');

      expect(ai.needsReconsentFor('Groq'), isFalse,
          reason: 'same recipient, already agreed');
      expect(
          ai.needsReconsentFor('Puter, which passes it to Anthropic'), isTrue,
          reason: 'different company, so it has not been agreed to');
    });

    test('the recipient survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await ai.clear();
      await ai.grant(source: 'connect', company: 'Groq');
      await ai.loadCached();

      expect(ai.consentedCompany, 'Groq',
          reason: 'otherwise every launch would re-ask');
    });

    test('nobody is re-asked when they have not agreed at all', () async {
      // needsReconsentFor is about a *change* of recipient. With no agreement
      // on file, mustAsk is the thing that applies, and double-counting would
      // show the disclosure twice.
      SharedPreferences.setMockInitialValues({});
      await ai.clear();
      await ai.loadCached();

      expect(ai.needsReconsentFor('anyone'), isFalse);
      expect(ai.mustAsk, isTrue);
    });
  });

  group('an unreachable server cannot stop somebody answering', () {
    // The bug these pin shipped: grant() was the POST and nothing else, so with
    // no endpoint deployed the consent screen threw, said "check your
    // connection", and saved nothing. Consent was impossible to give - the one
    // thing App Review asked us to provide. There is no auth token in a test,
    // so the sync is skipped exactly as it would be when the server is down.

    test('agreeing is recorded on the device and does not throw', () async {
      SharedPreferences.setMockInitialValues({});
      await ai.clear();

      await expectLater(ai.grant(source: 'connect'), completes);

      expect(ai.granted, isTrue, reason: 'the answer has to stick');
      expect(ai.needsDecision, isFalse);
      expect(ai.awaitingSync, isTrue, reason: 'and be known to still owe a sync');
    });

    test('declining is recorded too, and reads as a refusal', () async {
      SharedPreferences.setMockInitialValues({});
      await ai.clear();

      await expectLater(ai.withdraw(source: 'settings'), completes);

      expect(ai.declined, isTrue);
      expect(ai.granted, isFalse);
    });

    test('the answer survives a restart', () async {
      SharedPreferences.setMockInitialValues({});
      await ai.clear();
      await ai.grant(source: 'connect');

      // A fresh boot reads prefs and nothing else.
      await ai.loadCached();

      expect(ai.granted, isTrue, reason: 'asked once means asked once');
      expect(ai.awaitingSync, isTrue, reason: 'so the retry can still happen');
    });

    test('the recorded answer names the disclosure it was given against',
        () async {
      SharedPreferences.setMockInitialValues({});
      await ai.clear();
      await ai.grant(source: 'connect');

      expect(ai.disclosureVersion, AiConsentProvider.disclosureVersionShown);
      expect(ai.decidedAt, isNotNull, reason: 'an audit trail needs a when');
    });
  });
}
