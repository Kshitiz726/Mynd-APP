import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/core/services/quote_search.dart';
import 'package:ourmynd/models/motivation.dart';
import 'package:ourmynd/providers/motivation_provider.dart';
import 'package:ourmynd/providers/mood_provider.dart';

/// The quotations are somebody else's words, so the only thing the app decides
/// is which themes to go and ask for. That decision is the whole feature, and
/// it is the part that has to answer to the mood rather than to the schedule.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<MotivationProvider> onboarded(
      {Set<MotivationCategory> cats = const {}}) async {
    final m = MotivationProvider();
    await m.load();
    await m.save(MotivationSettings(onboarded: true, categories: cats));
    return m;
  }

  test('every theme asked for is one the source actually indexes', () async {
    // A tag the API does not carry comes back as an empty list rather than an
    // error, so an invented theme is a silently wasted request.
    final m = await onboarded(cats: MotivationCategory.values.toSet());
    for (final mood in [null, ...Mood.values]) {
      for (final t in m.themesFor(mood)) {
        expect(QuoteSearch.themes, contains(t),
            reason: '"$t" is not a tag the quote source knows');
      }
    }
    m.dispose();
  });

  test('a rough day is not sold success', () async {
    final m = await onboarded();
    final rough = m.themesFor(Mood.rough);
    expect(rough, isNot(contains('Success')));
    expect(rough, isNot(contains('Motivational')));
    m.dispose();
  });

  test('a great day is allowed to aim high', () async {
    final m = await onboarded();
    expect(m.themesFor(Mood.great), contains('Success'));
    m.dispose();
  });

  test('the mood changes what gets asked for', () async {
    final m = await onboarded();
    expect(m.themesFor(Mood.rough).toSet(),
        isNot(equals(m.themesFor(Mood.great).toSet())));
    m.dispose();
  });

  test('the areas chosen at setup reach the request', () async {
    final m = await onboarded(cats: const {MotivationCategory.health});
    expect(m.themesFor(Mood.okay), contains('Health'));
    m.dispose();
  });

  test('a long quotation is refused rather than shown cut off', () {
    // The card gives two lines before it ellipses.
    expect(QuoteSearch.debugClean('x' * 400, 'Cicero'), isNull);
    expect(QuoteSearch.debugClean('Short and true.', 'Cicero'), isNotNull);
  });

  test('an unattributed quotation is not shown', () {
    // The whole premise is that somebody said it.
    expect(QuoteSearch.debugClean('Some words.', ''), isNull);
    expect(QuoteSearch.debugClean('Some words.', 'Unknown'), isNull);
    expect(QuoteSearch.debugClean('Some words.', 'Rumi')?.author, 'Rumi');
  });
}
