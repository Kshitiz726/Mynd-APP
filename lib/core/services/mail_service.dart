import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:enough_mail/enough_mail.dart';
import 'package:mailer/mailer.dart' as mailer;
import 'package:mailer/smtp_server.dart';

/// What to ask Gmail for about each message, as one IMAP FETCH data item list.
///
/// The parentheses are the whole point. enough_mail writes this string into the
/// command verbatim - it adds nothing - and IMAP's grammar only allows a bare
/// data item when there is exactly one of them. Sent as
/// `FETCH 10:22 ENVELOPE FLAGS BODY.PEEK[TEXT]<0.400>` the server parses
/// ENVELOPE, finds FLAGS where the command should have ended, and answers BAD.
/// Every inbox read failed on that, and because the failure was swallowed into
/// an empty list it looked like an empty inbox rather than a broken command.
///
/// BODY.PEEK, not BODY: peeking does not set \Seen, so summarising an inbox
/// cannot silently mark as read the very messages somebody asked about.
const String kFetchSpec = '(ENVELOPE FLAGS BODY.PEEK[TEXT]<0.400>)';

/// An inbox read that did not happen, as opposed to one that found nothing.
class MailReadException implements Exception {
  const MailReadException(this.detail);

  final String detail;

  @override
  String toString() => 'MailReadException: $detail';
}


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

  /// Left only so a connection made by the withdrawn one-tap route can be
  /// recognised and retired. Nothing writes it any more.
  static const _kCanRead = 'om_mail_can_read';

  String? _address;
  String? _displayName;
  bool _oauth = false;
  bool _loaded = false;

  /// The coach can put mail in somebody's outbox, and read the inbox.
  ///
  /// One credential does both now. An app password authenticates SMTP and
  /// IMAP alike, so there is no longer a state where the coach can send but
  /// cannot look, and no Google approval standing between somebody and either
  /// half of it.
  bool get canSend => isConnected;
  bool get canRead => isConnected;

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
      // A connection made by the withdrawn one-tap route has no credential
      // this app can still use: its access token came from a Google grant
      // that is no longer requested. Retiring it here means somebody meets
      // "not connected" and reconnects, rather than a send that fails at the
      // SMTP handshake with nothing useful to say.
      if (_oauth) {
        debugPrint('[mail] retiring a one-tap connection; app password now');
        await disconnect();
      }
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
  }

  /// The last few messages, as headers and snippets only.
  ///
  /// Metadata and Gmail's own snippet, never the full body: a summary needs to
  /// know who wrote, about what and roughly what it said, and pulling whole
  /// message bodies into a model prompt would send far more of somebody's
  /// private mail to a third party than the job requires.
  Future<List<MailSummary>> recent({int limit = 12, bool unreadOnly = false}) async {
    if (!canRead) {
      debugPrint('[mail] this account cannot read mail');
      return const [];
    }
    final addr = _address;
    final pass = await _storage.read(key: _kPassword);
    if (addr == null || pass == null || pass.isEmpty) return const [];

    // IMAP rather than the Gmail API, and that is the whole reason an app
    // password is enough to summarise somebody's inbox.
    //
    // The Gmail REST API needs gmail.readonly, which is a Google *restricted*
    // scope: OAuth verification plus an annual third-party security
    // assessment before any account outside the project's test list can grant
    // it. The same app password that authenticates SMTP authenticates IMAP,
    // so reading costs the user nothing they have not already set up for
    // sending, and costs this app no approval process at all.
    final client = ImapClient(isLogEnabled: false);
    try {
      await client
          .connectToServer('imap.gmail.com', 993, isSecure: true)
          .timeout(const Duration(seconds: 20));
      await client.login(addr, pass).timeout(const Duration(seconds: 20));
      final box = await client.selectInbox();

      final count = box.messagesExists;
      if (count == 0) return const [];

      // Newest first, and only the last stretch of the mailbox: fetching the
      // whole inbox to show twelve lines would be minutes of transfer on a
      // busy account.
      final from = count - (limit * 3) + 1;
      final sequence = MessageSequence.fromRange(from < 1 ? 1 : from, count);
      final fetch = await client
          .fetchMessages(sequence, kFetchSpec)
          .timeout(const Duration(seconds: 30));

      final out = <MailSummary>[];
      for (final m in fetch.messages.reversed) {
        final unread = !m.isSeen;
        if (unreadOnly && !unread) continue;
        final env = m.envelope;
        final sender = env?.from?.isNotEmpty == true
            ? (env!.from!.first.personalName ?? env.from!.first.email)
            : '';
        out.add(MailSummary(
          from: sender.isEmpty ? 'unknown sender' : sender,
          subject: env?.subject ?? '(no subject)',
          date: env?.date?.toIso8601String() ?? '',
          // BODY.PEEK leaves the message unread. Summarising somebody's inbox
          // must not mark it as read: that silently destroys the one piece of
          // state they were asking about.
          snippet: _snippetOf(m),
          unread: unread,
        ));
        if (out.length >= limit) break;
      }
      debugPrint('[mail] imap: ${out.length} messages '
          '(${out.where((m) => m.unread).length} unread)');
      return out;
    } catch (e) {
      // Rethrown, not swallowed into an empty list. Returning [] made a broken
      // FETCH, a refused login and a genuinely empty inbox the same answer, so
      // the coach cheerfully reported "nothing came back from your mail" while
      // the real problem was a malformed command it never got to hear about.
      debugPrint('[mail] imap read failed: $e');
      throw MailReadException('$e');
    } finally {
      try {
        await client.logout();
      } catch (_) {/* the socket is going away regardless */}
    }
  }

  /// Just the unread ones. What "anything new?" actually means.
  Future<List<MailSummary>> unread({int limit = 12}) =>
      recent(limit: limit, unreadOnly: true);

  /// A readable first line or two of a message, from whatever it turned out
  /// to be. Never the whole body: a summary needs the gist, and a full body in
  /// a model prompt sends far more of somebody's private mail than the job
  /// requires.
  static String _snippetOf(MimeMessage m) {
    String raw;
    try {
      raw = m.decodeTextPlainPart() ?? m.decodeContentText() ?? '';
    } catch (_) {
      raw = '';
    }
    final flat = raw
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll(RegExp(r'https?://\S+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (flat.isEmpty) return '';
    return flat.length > 200 ? '${flat.substring(0, 200)}…' : flat;
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

    // Read at the moment of sending and dropped again, never held in a field:
    // a heap dump of a running app should not contain somebody's credential.
    final pass = await _storage.read(key: _kPassword);
    if (pass == null || pass.isEmpty) {
      return const MailResult.failure(
          'No credential saved for this account. Reconnect it in Settings.');
    }
    final SmtpServer server = gmail(addr, pass);

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
