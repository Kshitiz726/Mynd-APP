import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/coach_prompt_builder.dart';
import 'package:ourmynd/core/services/soul_service.dart';
import 'package:ourmynd/models/agent.dart';
import 'package:ourmynd/models/chat_message.dart';
import 'package:ourmynd/models/coach_context.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The voice, pinned.
///
/// Reported as "the agent responses are very generic and static, they have no
/// soul", and specifically the habit of ending on "want to do this?". That
/// habit came from an explicit instruction to end on a question, so it was not
/// the model being lazy, it was the prompt asking for it.
///
/// None of this can be checked by looking at a reply, because a reply is one
/// sample of a distribution. What can be checked is that the instruction which
/// produced it is gone and the one replacing it is present.
CoachContext plain() => const CoachContext(
      userName: 'sam',
      currentEnergyLevel: 'low',
      recentMoodLogs: [],
      recentBrainDumps: [],
      todayTasks: [],
      habitProgress: HabitProgress(
          completedToday: 0,
          totalHabits: 0,
          longestStreakName: null,
          longestStreakDays: 0),
      focusStatistics: FocusStatistics(
          sessionsToday: 0, minutesFocusedToday: 0, currentStreakDays: 0),
      previousConversationSummary: '',
      userPreferences: CoachUserPreferences(),
      detectedPatterns: [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final builder = CoachPromptBuilder.instance;

  String system({String soul = ''}) => builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'i cannot start this',
        soulBlock: soul,
      ).first['content']!;

  group('the habit that made it read like a bot', () {
    test('no agent is told to end on a question any more', () {
      for (final a in Agent.all) {
        final block = a.defaults.promptBlock;
        expect(block, isNot(contains('End on one question')),
            reason: '${a.name} is still being told to end on a question');
      }
    });

    test('every agent is told not to offer to do things', () {
      for (final a in Agent.all) {
        expect(a.defaults.promptBlock.toLowerCase(),
            anyOf(contains('never end by offering'), contains('say the thing')),
            reason: '${a.name} has nothing stopping "want to do this?"');
      }
    });

    test('the system prompt bans the offer-question outright', () {
      final s = system();
      expect(s, contains('want to do this?'));
      expect(s, contains('Do not ask permission to be useful'));
      expect(s, contains('React before you respond'.toUpperCase()));
    });

    test('it is told not to name the feeling back at them', () {
      expect(system(), contains('name their emotion back'));
    });
  });

  group('today does not come from long term memory', () {
    test('the prompt says which block is the truth about today', () {
      final s = system();
      expect(s, contains('TODAY IS NOT IN YOUR MEMORY'));
      expect(s, contains('THEIR DAY block is the only truth'));
      expect(s, contains('frequently out of date'));
    });

    test('with no day block it is told to say so rather than recite', () {
      expect(system(), contains('you do not know what is on today'));
    });
  });

  group('the soul document', () {
    test('reaches the prompt when there is one', () {
      final s = system(soul: 'HOW TO BE\nBe short. Swear back.');
      expect(s, contains('Be short. Swear back.'));
    });

    test('an empty one changes nothing and breaks nothing', () {
      expect(() => system(), returnsNormally);
    });

    test('condensing keeps the instructions and drops the furniture', () {
      const md = '''
# SOUL

Some explanation nobody needs in a prompt.

## The failure

- **The offer-question ending.** Never do this.

| What is going on | How to be |
|---|---|
| Overwhelmed | Slow and short. |
''';
      final out = SoulService.condenseForTest(md);
      expect(out, contains('THE FAILURE'));
      expect(out, contains('The offer-question ending.'));
      expect(out, contains('Overwhelmed: Slow and short.'));
      expect(out, isNot(contains('**')));
      expect(out, isNot(contains('|---')));
      expect(out, isNot(contains('# SOUL')));
    });
  });
}
