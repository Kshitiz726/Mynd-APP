import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/providers/ai_consent_provider.dart';

/// The app and the server each name the disclosure version independently, and
/// they have to agree.
///
/// If the server's version moves ahead, it reports every agreement given
/// against the app's older wording as undecided, and the user is asked again on
/// every launch with no way to settle it. If the app's moves ahead, it claims
/// agreement to wording the server has never heard of. Neither fails loudly,
/// which is why this reads the server source and compares.
void main() {
  test('the app and the server agree on the disclosure version', () {
    final source = File('server/src/routes/consent.ts').readAsStringSync();

    final match = RegExp(r"""AI_DISCLOSURE_VERSION\s*=\s*['"]([^'"]+)['"]""")
        .firstMatch(source);

    expect(match, isNotNull,
        reason: 'AI_DISCLOSURE_VERSION is no longer declared the way this test '
            'looks for it, so it can no longer check the two agree');

    expect(
      AiConsentProvider.disclosureVersionShown,
      match!.group(1),
      reason: 'AiConsentProvider.disclosureVersionShown and the server\'s '
          'AI_DISCLOSURE_VERSION must be the same string',
    );
  });
}
