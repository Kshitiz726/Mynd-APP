import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/feed_safety.dart';

/// The feed writes against an instruction document the user controls, so
/// without this "bring me porn" is a working instruction. This is the one part
/// of the feed that is not up to the user.
void main() {
  group('what the feed will not carry', () {
    test('a request for it in the instructions is refused', () {
      for (final line in [
        'bring me porn',
        'I want NSFW stuff',
        'more hentai please',
        'find me nude photos',
        'sexy news only',
      ]) {
        expect(isUnsafeForFeed(line, strict: true), isTrue, reason: line);
      }
    });

    test('an article about it is refused', () {
      expect(
          isUnsafeForFeed('The rise of OnlyFans creators and their earnings'),
          isTrue);
    });

    test('one bad line costs that line, not the whole document', () {
      const doc = 'Focus and attention research I can try.\n'
          'Bring me porn.\n'
          'One genuinely good thing that happened.';
      final kept = stripUnsafeInstructions(doc);

      expect(kept, contains('Focus and attention research'));
      expect(kept, contains('One genuinely good thing'));
      expect(kept.toLowerCase(), isNot(contains('porn')));
    });
  });

  group('what it must still carry', () {
    test('journalism that happens to use the word is not blocked', () {
      // A safety filter that silently eats the coverage that matters most is
      // its own kind of harm.
      for (final headline in [
        'Man convicted of sexual assault in landmark trial',
        'New sexual health education guidance for schools',
        'Court hears evidence in trafficking and exploitation case',
      ]) {
        expect(isUnsafeForFeed(headline), isFalse, reason: headline);
      }
    });

    test('words that merely contain a blocked word are untouched', () {
      // Substring matching rejects all of these. Word boundaries do not.
      for (final headline in [
        'Middlesex council approves the new library',
        'Sexism in hiring: what the new study found',
        'Essex flood defences upgraded this winter',
      ]) {
        expect(isUnsafeForFeed(headline), isFalse, reason: headline);
      }
    });

    test('the default instruction document is fine', () {
      expect(isUnsafeForFeed('Bring me things I can act on: focus and '
          'attention research, sleep and energy.', strict: true), isFalse);
    });
  });
}
