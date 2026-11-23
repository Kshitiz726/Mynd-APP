import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/services/api_client.dart';
import '../core/services/api_config.dart';

/// Whether this account has agreed to its coach messages being sent to the
/// third-party AI provider, and the single place anything in the app asks that.
///
/// This is the sibling of [HealthConsentProvider] and deliberately a separate
/// object, because it answers a different question. Health consent governs
/// whether mood and memory are *added* to a prompt; this governs whether the
/// prompt may be sent to the provider at all. The coach cannot run without the
/// second - the provider is where the reply comes from - so where health
/// consent fails open on the coach (decline and it still runs, just colder),
/// this one gates the coach itself.
///
/// The answer is recorded here first and synced to the server after. The three
/// things App Review requires - disclose, ask, do not send until they agree -
/// all happen on the phone, so the phone is where the answer has to be writable:
/// an earlier version recorded it only by POST, and when that endpoint could not
/// be reached the screen said "check your connection" and saved nothing, leaving
/// consent impossible to give. The server copy is the audit trail and the
/// cross-device answer, and it is allowed to arrive late.
///
/// The server still enforces the gate on its own send path, so a local yes that
/// has not synced yet cannot talk anybody's data past the server.
///
/// **It fails closed.** Before the first successful fetch, and whenever the
/// answer cannot be established, [granted] is false - nothing is sent to the
/// provider on an unknown answer. Access, separately, fails open: see [mustAsk].
class AiConsentProvider extends ChangeNotifier {
  AiConsentProvider._();
  static final AiConsentProvider instance = AiConsentProvider._();

  /// The disclosure the app currently shows. Must equal `AI_DISCLOSURE_VERSION`
  /// in `server/src/routes/consent.ts`; a test asserts that it does, because if
  /// the two drift the server treats every fresh agreement as stale and asks
  /// again forever.
  static const disclosureVersionShown = '2026-11-22';

  static const _kGranted = 'om_ai_consent_granted';
  static const _kDecidedAt = 'om_ai_consent_decided_at';
  static const _kVersion = 'om_ai_consent_version';
  static const _kUnsynced = 'om_ai_consent_unsynced';
  static const _kCompany = 'om_ai_consent_company';

  /// null = never answered (or answered against a disclosure version that has
  /// since been superseded), true = agreed, false = declined or withdrawn.
  bool? _granted;
  bool? get answer => _granted;

  DateTime? _decidedAt;

  /// When they last answered, either way. Shown in Settings.
  DateTime? get decidedAt => _decidedAt;

  String? _disclosureVersion;

  /// The disclosure version their stored answer was given against.
  String? get disclosureVersion => _disclosureVersion;

  String? _company;

  /// Who the answer was given about.
  ///
  /// Agreement is to a named recipient, not to the abstract idea of an AI.
  /// Guideline 5.1.2(i) asks the app to specify who the data is sent to, and
  /// somebody who agreed to the built-in model has not agreed to their words
  /// going to Anthropic through Puter. Storing the company is what lets the
  /// app notice that and ask again.
  String? get consentedCompany => _company;

  /// True when there is agreement on file, but for a different recipient than
  /// the one about to receive the data.
  bool needsReconsentFor(String company) =>
      granted && _company != null && _company != company;

  bool _loaded = false;
  bool get loaded => _loaded;

  /// The gate. Messages may be sent to the provider only when this is true.
  bool get granted => _granted == true;

  /// True when the stored answer is absent: never asked, or asked against a
  /// disclosure that no longer stands. About the record, not about whether to
  /// interrupt - use [mustAsk] for that.
  bool get needsDecision => _granted == null;

  bool _confirmedByServer = false;

  /// Whether the server has told us what it has on file. Nothing gates on this
  /// any more; it is kept because it is genuinely useful to know, and Settings
  /// distinguishes "saved here" from "saved on your account" with it.
  bool get confirmedByServer => _confirmedByServer;

  /// Whether to put the disclosure in front of the user right now.
  ///
  /// Asked as soon as there is no answer on file, which is the only answer
  /// compatible with the guideline: 5.1.2(i) requires permission *before*
  /// personal data reaches a third-party AI, so "we could not check, carry on
  /// sending" is the one behaviour that is definitely wrong.
  ///
  /// This used to also require the server to confirm there was no answer, so
  /// that nobody was shown a question whose answer could not be recorded. That
  /// reasoning was sound when the answer was recorded by POST and nothing else.
  /// It is not any more: [grant] and [withdraw] write to the device first and
  /// sync afterwards, so the question can always be answered. What the old
  /// condition actually did, with `/consent/ai` returning 404 on both servers,
  /// was make `mustAsk` permanently false - so the disclosure never appeared
  /// and the chat sent messages to the provider without ever asking. The exact
  /// violation the screen exists to prevent.
  ///
  /// [loaded] is still required, so a cold start reads the stored answer before
  /// deciding, rather than flashing the disclosure at somebody who agreed
  /// months ago.
  bool get mustAsk => _loaded && needsDecision;

  /// They were asked and said no. The coach is unavailable, but the rest of the
  /// app is not, and this is what the coach gate reads to show that state
  /// rather than silently looping the disclosure.
  bool get declined => _granted == false;

  /// Read the cached answer from disk, during boot, before the first frame.
  Future<void> loadCached() async {
    try {
      final p = await SharedPreferences.getInstance();
      // containsKey, not a defaulted getter: "absent" is a third state that a
      // default would collapse into "declined".
      _granted = p.containsKey(_kGranted) ? p.getBool(_kGranted) : null;
      final at = p.getString(_kDecidedAt);
      _decidedAt = at == null ? null : DateTime.tryParse(at);
      _disclosureVersion = p.getString(_kVersion);
      _unsynced = p.getBool(_kUnsynced) ?? false;
      _company = p.getString(_kCompany);
    } catch (e) {
      debugPrint('[ai-consent] cached read failed: $e');
    }
    _loaded = true;
    notifyListeners();
  }

  /// An answer is on this phone that the server has not acknowledged yet.
  bool _unsynced = false;

  /// Whether the stored answer still needs to reach the server. Settings shows
  /// it, so "saved on this device" is never mistaken for "saved everywhere".
  bool get awaitingSync => _unsynced;

  /// Ask the server. Its answer replaces the cache, including the case where
  /// the disclosure has moved on and a previous agreement comes back undecided.
  Future<void> refresh() async {
    if (ApiConfig.instance.authToken == null) return;

    // Push before pulling. Otherwise a local answer that has not synced yet is
    // overwritten by the server's "no answer on file" and the user is asked
    // something they already answered.
    if (_unsynced) {
      await _push(source: 'retry');
      if (_unsynced) return;
    }

    try {
      final j = await ApiClient.instance.fetchAiConsent();
      await _apply(j);
    } catch (e) {
      // A server we cannot reach is not a withdrawal. Leave the cache in place
      // rather than taking the coach away from someone on a bad connection.
      debugPrint('[ai-consent] refresh failed, keeping cached answer: $e');
    }
  }

  /// Record agreement. [source] is where it was asked; [company] is who the
  /// data will reach, which is the thing actually being agreed to.
  Future<void> grant({required String source, String? company}) =>
      _record(true, source, company);

  /// Record a decline, or a withdrawal of agreement already given. One call:
  /// to the record they are the same present fact, and the audit trail tells
  /// them apart by what came before.
  Future<void> withdraw({required String source, String? company}) =>
      _record(false, source, company);

  /// Write the answer down here, then tell the server.
  ///
  /// This order matters and it is the fix for a real failure: the record used
  /// to be made by the POST alone, so when the endpoint was unreachable the
  /// screen threw, showed "check your connection", and left the answer
  /// unrecorded. Consent was impossible to give, which is the exact thing
  /// App Review asked us to provide.
  ///
  /// Recording locally first is also the honest model of what consent is. The
  /// requirement is that this app discloses, asks, and does not send until the
  /// person agrees, and all three of those happen on the phone. The server copy
  /// is the audit trail and the cross-device answer, and it is allowed to
  /// arrive late. Nothing is sent to the provider in the meantime unless the
  /// answer here is a definite yes, so a deferred sync can only ever be more
  /// conservative than the user asked for, never less.
  Future<void> _record(bool granted, String source, String? company) async {
    _granted = granted;
    _decidedAt = DateTime.now().toUtc();
    _disclosureVersion = disclosureVersionShown;
    _company = company;
    _unsynced = true;
    _loaded = true;
    notifyListeners();

    await _persist();
    await _push(source: source);
  }

  /// Best effort. Leaves [_unsynced] set when it does not land, so [refresh]
  /// tries again on the next launch or settings visit.
  Future<void> _push({required String source}) async {
    final g = _granted;
    if (g == null || ApiConfig.instance.authToken == null) return;
    try {
      final j = await ApiClient.instance.setAiConsent(granted: g, source: source);
      await _apply(j);
    } catch (e) {
      debugPrint('[ai-consent] not synced yet, keeping the local answer: $e');
    }
  }

  /// Forget the cached answer when the signed-in account changes, so the next
  /// account is never gated by the previous one's decision.
  Future<void> clear() async {
    _granted = null;
    _decidedAt = null;
    _disclosureVersion = null;
    _confirmedByServer = false;
    _unsynced = false;
    _company = null;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove(_kGranted);
      await p.remove(_kDecidedAt);
      await p.remove(_kVersion);
      await p.remove(_kUnsynced);
      await p.remove(_kCompany);
    } catch (e) {
      debugPrint('[ai-consent] clear failed: $e');
    }
  }

  Future<void> _apply(Map<String, dynamic> j) async {
    _confirmedByServer = true;
    _granted = j['granted'] as bool?;
    final at = j['decidedAt'] as String?;
    _decidedAt = at == null ? null : DateTime.tryParse(at);
    _disclosureVersion = j['disclosureVersion'] as String?;
    // The server has spoken, so whatever was waiting to reach it has.
    _unsynced = false;
    _loaded = true;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      final g = _granted;
      if (g == null) {
        await p.remove(_kGranted);
      } else {
        await p.setBool(_kGranted, g);
      }
      final d = _decidedAt;
      if (d == null) {
        await p.remove(_kDecidedAt);
      } else {
        await p.setString(_kDecidedAt, d.toIso8601String());
      }
      final v = _disclosureVersion;
      if (v == null) {
        await p.remove(_kVersion);
      } else {
        await p.setString(_kVersion, v);
      }
      if (_unsynced) {
        await p.setBool(_kUnsynced, true);
      } else {
        await p.remove(_kUnsynced);
      }
      final co = _company;
      if (co == null) {
        await p.remove(_kCompany);
      } else {
        await p.setString(_kCompany, co);
      }
    } catch (e) {
      debugPrint('[ai-consent] cache write failed: $e');
    }
  }
}
