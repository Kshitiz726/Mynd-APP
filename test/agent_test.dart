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
    await p.select('sprout');

    final block = p.promptBlock;
    expect(block, contains('SPROUT'));
    expect(block, contains('playful'));
    // Sprout ships warm, funny and high energy.
    expect(block, contains('openly warm'));
    expect(block, contains('Be funny'));
  });

  test('the shipped personalities really are different in the prompt',
      () async {
    final p = AgentProvider();
    await p.init();

    await p.select('sprout');
    final blunt = p.promptBlock;
    await p.select('pim');
    final gentle = p.promptBlock;

    expect(blunt, isNot(gentle));
  });

  test('tuning one agent leaves the others alone', () async {
    final p = AgentProvider();
    await p.init();

    final sprout = Agent.byId('sprout');
    final pim = Agent.byId('pim');

    await p.update(sprout, p.settingsFor(sprout).copyWith(humour: 1.0));

    expect(p.isCustomised(sprout), isTrue);
    expect(p.isCustomised(pim), isFalse,
        reason: 'settings are per agent, not a shared block');
    expect(p.settingsFor(pim).humour, pim.defaults.humour);
  });

  test('a tuned agent survives a restart, and reset only clears that one',
      () async {
    final first = AgentProvider();
    await first.init();
    final sprout = Agent.byId('sprout');
    await first.select('sprout');
    await first.update(
      sprout,
      first.settingsFor(sprout).copyWith(
            emotion: AgentEmotion.gentle,
            custom: 'Call me by my first name.',
          ),
    );

    // A fresh provider over the same storage is what the next launch sees.
    final second = AgentProvider();
    await second.init();
    expect(second.selectedId, 'sprout');
    expect(second.settingsFor(sprout).emotion, AgentEmotion.gentle);
    expect(second.promptBlock, contains('Call me by my first name.'));

    await second.resetToDefaults(sprout);
    expect(second.settingsFor(sprout).emotion, sprout.defaults.emotion);
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
  test('only the two agents whose artwork is ours are shipped', () {
    expect(Agent.all.map((a) => a.id), ['pim', 'sprout']);
    for (final a in Agent.all) {
      expect(a.asset, anyOf(endsWith('avatar1.jpg'), endsWith('avatar2.jpg')),
          reason: '${a.name} uses withdrawn artwork');
    }
  });

  test('somebody who had a withdrawn agent selected gets a real one', () async {
    SharedPreferences.setMockInitialValues({'om_agent_selected': 'blitz'});
    final p = AgentProvider();
    await p.init();

    // Not just the agent object: the id itself has to settle, or the picker
    // shows nothing selected while the coach answers as somebody.
    expect(p.selectedId, 'pim');
    expect(p.agent.name, 'Pim');
  });
}
