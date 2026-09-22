import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

import 'google_auth.dart';

/// Sending mail as the user, from the user's own device.
///
/// The credential never leaves the phone. The app talks to Gmail's SMTP server
/// directly rather than handing the password to our server to send on their
/// behalf, because the moment a password is posted to a backend it exists in
/// that backend's memory, its logs and its crash reports, and we would be
/// asking people to trust us with the keys to their whole email account. This
/// way the only two parties who ever hold it are the user and Google.
///
/// It is stored in the platform keystore via [FlutterSecureStorage] - Keychain
/// on iOS, AES-GCM under a hardware-wrapped key on Android - and not in
/// SharedPreferences, which is a plain file any backup can read.
///
/// An **app password**, not the account password. Google issues 16-character
/// app passwords that work for SMTP only, are revocable one by one from the
/// Google account page, and are useless for signing in to anything. Asking for
/// the real password would be asking for the account itself, and with 2FA on
/// it would not even work.
class MailService {
  MailService._();

  /// Constructible only by a test double. Everything real goes through
  /// [instance].
  @visibleForTesting
  MailService.forTesting();

  static MailService _instance = MailService._();

  static MailService get instance => _instance;

  /// Swap in a double for a test.
  ///
  /// The path from "send this to Sam" to a bubble saying whether it went is
  /// the part that keeps being wrong, and it is untestable while the transport
  /// is a hard-wired singleton: proving it needs a real credential and a real
  /// message arriving in somebody's inbox.
  @visibleForTesting
  static set instance(MailService m) => _instance = m;

  /// Put the real one back. Every test that sets [instance] calls this.
  @visibleForTesting
  static void resetInstance() => _instance = MailService._();

  // first_unlock rather than the default: the coach may be asked to send mail
  // from a notification action or straight after a cold start, and the stricter
  // accessibility levels would fail to read the key on a device that has not
  // been unlocked since boot.
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const _kAddress = 'om_mail_address';
  static const _kPassword = 'om_mail_app_password';
  static const _kName = 'om_mail_display_name';

  /// Set when the account was connected with one tap rather than a password.
  static const _kOauth = 'om_mail_oauth';

  /// Set when Gmail granted the read scope. Sending and reading are asked for
  /// separately, so one can be granted without the other.
  static const _kCanRead = 'om_mail_can_read';

  /// Sending. A Google *sensitive* scope: it needs the OAuth client verified
  /// before it works for the public, and nothing more than that.
  static const sendScope = 'https://www.googleapis.com/auth/gmail.send';

  /// Reading enough of the inbox to summarise it. A Google *restricted* scope,
  /// which is a considerably higher bar: verification plus an annual
  /// third-party security assessment (CASA).
  static const readScope = 'https://www.googleapis.com/auth/gmail.readonly';

  /// Asked for separately, and this is the point rather than tidiness.
  ///
  /// They used to be requested as one list, so the harder permission decided
  /// the outcome of the easier one: an account that could not have the
  /// restricted read scope was refused the sensitive send scope with it, and
  /// the connection failed as a whole. Sending is the thing people ask the
  /// coach to do, and it is the half that clears the lower bar, so it is now
  /// asked for first and kept whatever happens to the other.
  static const gmailScopes = <String>[sendScope, readScope];

  String? _address;
  String? _displayName;
  bool _oauth = false;
  bool _canRead = false;
  bool _loaded = false;

  /// The coach can put mail in somebody's outbox.
  ///
  /// An app password connection can always send; that is all it is for. An
  /// OAuth connection can send because the send scope was granted, which is
  /// the only reason an address was stored at all.
  bool get canSend => isConnected;

  /// The coach can look at the inbox. False on an app password connection,
  /// which is SMTP only, and false when Google refused the restricted scope.
  bool get canRead => isConnected && _oauth && _canRead;

  /// True when this account is connected through the Google sign-in the user
  /// already did, rather than by typing an app password.
  bool get isOauth => _oauth;

  /// The connected address, or null. Safe to show: it is the user's own, and
  /// they need to see which account is about to send.
  String? get address => _address;

  /// What the recipient sees in the From line.
  String? get displayName => _displayName;

  bool get isConnected => _address != null && _address!.isNotEmpty;
  bool get loaded => _loaded;

  /// Read what is stored. The password is deliberately *not* held in memory
  /// here: it is fetched at the moment of sending and dropped again, so a heap
  /// dump of a running app does not contain it.
  Future<void> init() async {
    try {
      _address = await _storage.read(key: _kAddress);
      _displayName = await _storage.read(key: _kName);
      _oauth = (await _storage.read(key: _kOauth)) == '1';
      _canRead = (await _storage.read(key: _kCanRead)) == '1';
    } catch (e) {
      // A locked or unavailable keychain must not stop the app booting.
      debugPrint('[mail] could not read the keychain: $e');
    }
    _loaded = true;
    // Said out loud at every boot. Whether mail is connected decides which
    // half of the coach's prompt it gets, and the symptom of getting it wrong
    // is the coach politely offering to draft instead of sending, which looks
    // like the model being unhelpful rather than a missing grant.
    debugPrint('[mail] connected=$isConnected oauth=$_oauth '
        'canSend=$canSend canRead=$canRead');
  }

  /// Save the account. [appPassword] goes to the keychain and is never logged,
  /// never printed and never sent anywhere but Gmail's SMTP server.
  Future<void> connect({
    required String address,
    required String appPassword,
    String? displayName,
  }) async {
    final addr = address.trim();
    // Gmail app passwords are shown in four groups of four. People paste them
    // with the spaces in, and Google accepts them either way, so strip rather
    // than reject: a validation error on a correctly pasted password is a
    // support ticket nobody needs.
    final pass = appPassword.replaceAll(RegExp(r'\s'), '');
    await _storage.write(key: _kAddress, value: addr);
    await _storage.write(key: _kPassword, value: pass);
    if (displayName != null && displayName.trim().isNotEmpty) {
      await _storage.write(key: _kName, value: displayName.trim());
      _displayName = displayName.trim();
    }
    _address = addr;
  }

  /// Connect the account the user already signed in with, in one tap.
  ///
  /// No password to find, generate, copy or paste. They granted us their
  /// identity at sign-in; this asks for two more permissions on the same
  /// account and nothing else.
  ///
  /// Nothing secret is stored. The access token is short lived and is fetched
  /// fresh from the Google session at the moment of each send, so there is no
  /// long-lived credential of ours sitting on the device to leak, and
  /// revoking the grant in the Google account page takes effect immediately
  /// rather than whenever we happen to notice.
  Future<MailResult> connectWithGoogle() async {
    if (!GoogleAuth.supported) {
      return const MailResult.failure(
          'Google sign-in is not available on this device.');
    }
    try {
      var account = GoogleAuth.instance.currentUser ??
          await GoogleAuth.instance.signInSilently();
      account ??= await GoogleAuth.instance.signIn();
      if (account == null) {
        return const MailResult.failure('Cancelled.');
      }

      // Sending first, and on its own. This is the half that only needs the
      // client verified, and the half people actually ask for.
      final canSend = await GoogleAuth.instance.requestScopes([sendScope]);
      if (!canSend) {
        return const MailResult.failure(
            'Google did not grant permission to send. Until this app is '
            'verified, that permission is only given to accounts on its test '
            'list in the Google Cloud console.');
      }

      // Reading is asked for separately and is allowed to fail. It is a
      // restricted scope, so it needs an annual security assessment on top of
      // verification, and refusing it must not cost the connection.
      var canRead = false;
      try {
        canRead = await GoogleAuth.instance.requestScopes([readScope]);
      } catch (e) {
        debugPrint('[mail] read scope refused: $e');
      }

      await _storage.write(key: _kAddress, value: account.email);
      await _storage.write(key: _kOauth, value: '1');
      await _storage.write(key: _kCanRead, value: canRead ? '1' : '0');
      _canRead = canRead;
      // No app password in play any more; make sure an old one cannot be
      // picked up by the send path in preference to the grant.
      await _storage.delete(key: _kPassword);
      final name = account.displayName;
      if (name != null && name.trim().isNotEmpty) {
        await _storage.write(key: _kName, value: name.trim());
        _displayName = name.trim();
      }
      _address = account.email;
      _oauth = true;

      // The message says what was actually granted. "Connected" on its own is
      // how somebody ends up asking why their coach cannot see an inbox it
      // was never given permission to look at.
      return MailResult.success(canRead
          ? 'Connected as ${account.email}. Your coach can send mail and read '
              'your recent inbox.'
          : 'Connected as ${account.email}. Your coach can send mail. Reading '
              'your inbox was not granted, so it cannot summarise it yet.');
    } catch (e) {
      debugPrint('[mail] one-tap connect failed: $e');
      return MailResult.failure(_explain(e));
    }
  }

  /// A live Gmail access token for the signed-in account, or null.
  Future<String?> _accessToken() async {
    try {
      final account = GoogleAuth.instance.currentUser ??
          await GoogleAuth.instance.signInSilently();
      if (account == null) return null;
      final auth = await account.authentication;
      return auth.accessToken;
    } catch (e) {
      debugPrint('[mail] could not get an access token: $e');
      return null;
    }
  }

  /// Forget the account entirely. Does not revoke anything at Google - only
  /// the user can do that, and the disconnect screen says so.
  Future<void> disconnect() async {
    await _storage.delete(key: _kAddress);
    await _storage.delete(key: _kPassword);
    await _storage.delete(key: _kName);
    await _storage.delete(key: _kOauth);
    await _storage.delete(key: _kCanRead);
    _address = null;
    _displayName = null;
    _oauth = false;
    _canRead = false;
  }

  /// The last few messages, as headers and snippets only.
  ///
  /// Metadata and Gmail's own snippet, never the full body: a summary needs to
  /// know who wrote, about what and roughly what it said, and pulling whole
  /// message bodies into a model prompt would send far more of somebody's
  /// private mail to a third party than the job requires.
  Future<List<MailSummary>> recent({int limit = 12}) async {
    if (!canRead) {
      debugPrint('[mail] no read grant on this account');
      return const [];
    }
    final token = await _accessToken();
    if (token == null || !isConnected) return const [];
    final headers = {'Authorization': 'Bearer $token'};
    try {
      final listRes = await http
          .get(
            Uri.https('gmail.googleapis.com', '/gmail/v1/users/me/messages', {
              'maxResults': '$limit',
              // Recent and actually in the inbox. Promotions and social are
              // noise in a summary somebody asked for.
              'q': 'in:inbox newer_than:7d -category:promotions -category:social',
            }),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));
      if (listRes.statusCode != 200) {
        debugPrint('[mail] list failed: ${listRes.statusCode}');
        return const [];
      }
      final ids = ((jsonDecode(listRes.body)['messages'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => m['id'] as String?)
          .whereType<String>()
          .toList();

      final out = <MailSummary>[];
      await Future.wait(ids.map((id) async {
        try {
          final r = await http
              .get(
                Uri.https(
                  'gmail.googleapis.com',
                  '/gmail/v1/users/me/messages/$id',
                  {
                    'format': 'metadata',
                    'metadataHeaders': 'From,Subject,Date',
                  },
                ),
                headers: headers,
              )
              .timeout(const Duration(seconds: 15));
          if (r.statusCode != 200) return;
          final j = jsonDecode(r.body) as Map<String, dynamic>;
          final hs = ((j['payload']?['headers'] as List?) ?? const [])
              .whereType<Map>();
          String head(String name) =>
              (hs.firstWhere((h) => (h['name'] as String?)?.toLowerCase() == name.toLowerCase(),
                          orElse: () => const {})['value'] as String?) ??
                  '';
          out.add(MailSummary(
            from: head('From'),
            subject: head('Subject'),
            date: head('Date'),
            snippet: (j['snippet'] as String?) ?? '',
            unread: ((j['labelIds'] as List?) ?? const []).contains('UNREAD'),
          ));
        } catch (_) {
          /* one unreadable message costs that message */
        }
      }));
      return out;
    } catch (e) {
      debugPrint('[mail] recent failed: $e');
      return const [];
    }
  }

  /// Prove the credential works before telling anyone they are connected, by
  /// sending one message to the user's own address.
  ///
  /// Actually sending is the only honest check this library allows: opening a
  /// connection does not authenticate, so a "connected" badge based on that
  /// would turn out to be wrong the first time the coach tried to send
  /// something - by which point the user has already told somebody the mail
  /// is on its way. It goes to their own inbox and nowhere else, and the
  /// screen says so before it runs.
  Future<MailResult> verify() async {
    final addr = _address;
    if (addr == null || addr.isEmpty) {
      return const MailResult.failure('No account connected.');
    }
    final r = await send(
      to: addr,
      subject: 'OurMynd is connected',
      body: 'This is the test message from OurMynd.\n\n'
          'Your Gmail account is connected, and your coach can send mail on '
          'your behalf when you ask it to.\n\n'
          'If you did not set this up, remove the app password from your '
          'Google account page straight away.',
    );
    return r.ok
        ? const MailResult.success(
            'Connected. A test message is in your inbox.')
        : r;
  }

  /// Send one message. Returns rather than throws: the caller is a chat turn,
  /// and an unhandled exception there loses the whole reply.
  Future<MailResult> send({
    required String to,
    required String subject,
    required String body,
  }) async {
    final addr = _address;
    if (addr == null || addr.isEmpty) {
      return const MailResult.failure(
          'No Gmail account is connected. Add one in Settings, under '
          'Connections.');
    }
    if (!isEmail(to)) {
      return MailResult.failure('"$to" does not look like an email address.');
    }

    // The grant first, a stored app password only if this account was
    // connected the old way. Both end at the same SMTP server; only the
    // credential differs.
    SmtpServer server;
    if (_oauth) {
      final token = await _accessToken();
      if (token == null) {
        return const MailResult.failure(
            'Your Google session expired. Open Connections and reconnect.');
      }
      server = gmailSaslXoauth2(addr, token);
    } else {
      final pass = await _storage.read(key: _kPassword);
      if (pass == null || pass.isEmpty) {
        return const MailResult.failure(
            'No credential saved for this account. Reconnect it in Settings.');
      }
      server = gmail(addr, pass);
    }

    try {
      final message = mailer.Message()
        ..from = mailer.Address(addr, _displayName ?? addr)
        ..recipients.add(to)
        ..subject = subject
        ..text = body;

      await mailer.send(message, server);
      return MailResult.success('Sent to $to.');
    } on mailer.MailerException catch (e) {
      return MailResult.failure(_explain(e));
    } catch (e) {
      return MailResult.failure(_explain(e));
    }
  }

  /// Deliberately plain, and deliberately not the raw exception.
  ///
  /// SMTP failures come back as long strings that can quote the credential
  /// back at you, and this text goes straight into a chat bubble the user can
  /// screenshot.
  static String _explain(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('username and password not accepted') ||
        s.contains('invalid credentials') ||
        s.contains('535')) {
      return 'Gmail refused that app password. Check it is an app password '
          'rather than your account password, and that 2-Step Verification is '
          'on.';
    }
    if (s.contains('timed out') || s.contains('socketexception')) {
      return 'Could not reach Gmail. Check the connection and try again.';
    }
    if (s.contains('access_denied') || s.contains('not been verified')) {
      return 'Google has not verified this app for Gmail access yet, so it '
          'can only be granted to accounts on the project test list.';
    }
    return 'Gmail would not send that one.';
  }

  static bool isEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());
}

@immutable
class MailResult {
  const MailResult.success(this.message) : ok = true;
  const MailResult.failure(this.message) : ok = false;

  final bool ok;
  final String message;
}

/// One message, as much of it as a summary needs and no more.
@immutable
class MailSummary {
  const MailSummary({
    required this.from,
    required this.subject,
    required this.date,
    required this.snippet,
    required this.unread,
  });

  final String from;
  final String subject;
  final String date;
  final String snippet;
  final bool unread;

  /// One compact line for the model. Deliberately short: a dozen of these go
  /// into a prompt, and the snippet is already Gmail's own summary.
  String get promptLine {
    final who = from.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    final body = snippet.length > 160 ? '${snippet.substring(0, 160)}…' : snippet;
    return '- ${unread ? '[unread] ' : ''}$who: "$subject" - $body';
  }
}
