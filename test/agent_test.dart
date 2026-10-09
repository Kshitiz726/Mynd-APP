import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ourmynd/models/agent.dart';
import 'package:ourmynd/providers/agent_provider.dart';

/// The promise of the picker is that choosing a face changes the coaching.
///
/// That promise is only kept if the persona and the tuning actually reach the
/// prompt, and if each agent's settings stay its own. Both are invisible on
/// screen: an avatar swap looks identical whether or not anything behind it
/// changed, which is exactly why it needs pinning here.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('every agent ships with a distinct persona and description', () {
    final personas = Agent.all.map((a) => a.persona).toSet();
    final names = Agent.all.map((a) => a.name).toSet();
    expect(personas.length, Agent.all.length,
        reason: 'two agents with the same persona are one agent in two hats');
    expect(names.length, Agent.all.length);
    for (final a in Agent.all) {
      expect(a.description.trim(), isNotEmpty);
      expect(a.bestFor.trim(), isNotEmpty,
          reason: 'an agent that is right for everyone is a skin');
      expect(a.asset, startsWith('assets/agents/'));
    }
  });

  test('the prompt block carries who the agent is and how it was tuned',
      () async {
    final p = AgentProvider();
    await p.init();
    await p.select('ember');

    final block = p.promptBlock;
    expect(block, contains('EMBER'));
    expect(block, contains('encouraging'));
    // Ember ships warm and high energy.
    expect(block, contains('openly warm'));
  });

  test('the shipped personalities really are different in the prompt',
      () async {
    final p = AgentProvider();
    await p.init();

    await p.select('ember');
    final bright = p.promptBlock;
    await p.select('hush');
    final quiet = p.promptBlock;

    expect(bright, isNot(quiet));
  });

  test('tuning one agent leaves the others alone', () async {
    final p = AgentProvider();
    await p.init();

    final ember = Agent.byId('ember');
    final hush = Agent.byId('hush');

    await p.update(ember, p.settingsFor(ember).copyWith(humour: 1.0));

    expect(p.isCustomised(ember), isTrue);
    expect(p.isCustomised(hush), isFalse,
        reason: 'settings are per agent, not a shared block');
    expect(p.settingsFor(hush).humour, hush.defaults.humour);
  });

  test('a tuned agent survives a restart, and reset only clears that one',
      () async {
    final first = AgentProvider();
    await first.init();
    final ember = Agent.byId('ember');
    await first.select('ember');
    await first.update(
      ember,
      first.settingsFor(ember).copyWith(
            emotion: AgentEmotion.gentle,
            custom: 'Call me by my first name.',
          ),
    );

    // A fresh provider over the same storage is what the next launch sees.
    final second = AgentProvider();
    await second.init();
    expect(second.selectedId, 'ember');
    expect(second.settingsFor(ember).emotion, AgentEmotion.gentle);
    expect(second.promptBlock, contains('Call me by my first name.'));

    await second.resetToDefaults(ember);
    expect(second.settingsFor(ember).emotion, ember.defaults.emotion);
    expect(second.promptBlock, isNot(contains('Call me by my first name.')));
  });

  test('custom wording is appended last so it can override a slider', () {
    const s = AgentSettings(warmth: 0, custom: 'Always be affectionate.');
    final lines = s.promptBlock.split('\n');
    expect(lines.last, contains('Always be affectionate.'));
    expect(lines.first, contains('matter of fact'),
        reason: 'the slider still states its case; the custom line wins by '
            'coming after it');
  });

  test('an unknown agent id falls back rather than throwing', () {
    expect(Agent.byId('nobody').id, Agent.fallback.id);
  });

  test('every emotion says something the model can act on', () {
    for (final e in AgentEmotion.values) {
      expect(e.instruction.trim(), isNotEmpty);
      expect(e.label.trim(), isNotEmpty);
      expect(e.glyph.trim(), isNotEmpty);
    }
  });

  /// Guideline 5.2.1, as a test rather than as a note in a commit message.
  ///
  /// Two of the four original faces were drawn closely on characters somebody
  /// else owns. They were withdrawn, and this is what stops them coming back
  /// the next time somebody wants more variety in the picker: the review that
  /// catches it otherwise is Apple's, after a submission.
  test('only the three agents whose artwork is ours are shipped', () {
    expect(Agent.all.map((a) => a.id), ['ember', 'hush', 'wren']);
    for (final a in Agent.all) {
      expect(a.asset, anyOf(endsWith('ember.png'), endsWith('hush.png'),
          endsWith('wren.png')),
          reason: '${a.name} uses withdrawn artwork');
    }
  });

  /// The faces are three moods, so the writing has to be three voices. An
  /// agent whose persona could be swapped for its neighbour's without anybody
  /// noticing is the "skin" failure this roster exists to avoid.
  test('each agent sounds like its own face', () {
    final ember = Agent.byId('ember');
    final hush = Agent.byId('hush');
    final wren = Agent.byId('wren');

    // Ember is the warm, high-energy one.
    expect(ember.defaults.energy, greaterThan(hush.defaults.energy));
    expect(ember.defaults.emotion, AgentEmotion.upbeat);

    // Hush is the quiet one, and says less on purpose.
    expect(hush.defaults.verbosity, Verbosity.brief);
    expect(hush.defaults.energy, lessThan(0.3));
    expect(hush.defaults.emotion, AgentEmotion.calm);

    // Wren takes worry seriously, which means it must never wave it away.
    expect(wren.defaults.emotion, AgentEmotion.gentle);
    expect(wren.persona, contains('never'));
    expect(wren.persona.toLowerCase(), contains('do not worry'),
        reason: 'the one rule Wren exists to follow is not in its persona');
  });

  test('somebody who had a withdrawn agent selected gets a real one', () async {
    SharedPreferences.setMockInitialValues({'om_agent_selected': 'blitz'});
    final p = AgentProvider();
    await p.init();

    // Not just the agent object: the id itself has to settle, or the picker
    // shows nothing selected while the coach answers as somebody.
    expect(p.selectedId, 'ember');
    expect(p.agent.name, 'Ember');
  });
}
