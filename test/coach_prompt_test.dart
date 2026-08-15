import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/coach_prompt_builder.dart';
import 'package:ourmynd/models/chat_message.dart';
import 'package:ourmynd/models/coach_context.dart';

/// The coach's memory should arrive when the turn is about them, and stay out
/// of the way when it is not.
void main() {
  final builder = CoachPromptBuilder.instance;

  CoachContext ctx() => const CoachContext(
        userName: 'sam',
        currentEnergyLevel: 'low',
        recentMoodLogs: [],
        recentBrainDumps: [],
        todayTasks: [
          TaskSummary(
              title: 'file the tax return', energyLevel: 'high', isDone: false),
        ],
        habitProgress: HabitProgress(
            completedToday: 0,
            totalHabits: 0,
            longestStreakName: null,
            longestStreakDays: 0),
        focusStatistics: FocusStatistics(
            sessionsToday: 0, minutesFocusedToday: 0, currentStreakDays: 0),
        previousConversationSummary:
            'they have been avoiding the tax return for two weeks',
        userPreferences: CoachUserPreferences(),
        detectedPatterns: [],
      );

  ChatMessage user(String t) =>
      ChatMessage(id: t, text: t, fromUser: true);
  ChatMessage bot(String t) =>
      ChatMessage(id: t, text: t, fromUser: false);

  String systemText(List<Map<String, String>> m) => m
      .where((x) => x['role'] == 'system')
      .map((x) => x['content']!)
      .join('\n');

  test('a question about their day carries their schedule', () {
    final m = builder.build(
      context: ctx(),
      history: const [],
      userMessage: 'what should i do with my day',
    );
    expect(systemText(m), contains('tax return'));
  });

  test('a general question does not', () {
    final m = builder.build(
      context: ctx(),
      history: const [],
      userMessage: 'explain how a diesel engine differs from a petrol one',
    );
    expect(systemText(m), isNot(contains('tax return')));
  });

  test('"tell me" is not enough to make a question personal', () {
    final m = builder.build(
      context: ctx(),
      history: const [],
      userMessage: 'can you tell me how promises work in javascript',
    );
    expect(systemText(m), isNot(contains('tax return')));
  });

  test('a state word does make it personal', () {
    final m = builder.build(
      context: ctx(),
      history: const [],
      userMessage: 'i am completely exhausted and cannot start anything at all',
    );
    expect(systemText(m), contains('tax return'));
  });

  test('a short follow-up keeps the thread personal', () {
    final m = builder.build(
      context: ctx(),
      history: const [],
      userMessage: 'yoyo',
    );
    expect(systemText(m), contains('tax return'));
  });

  test('context sticks across a thread that has turned personal', () {
    final m = builder.build(
      context: ctx(),
      history: [
        user('i keep putting off my tax return'),
        bot('what part of it feels heaviest'),
      ],
      // No keyword of its own, but plainly still about the same thing.
      userMessage: 'honestly the whole thing is just sitting there unopened',
    );
    expect(systemText(m), contains('tax return'));
  });

  test('the length cap is gone', () {
    final m = builder.build(
      context: ctx(),
      history: const [],
      userMessage: 'what is a closure in javascript',
    );
    final s = systemText(m);
    expect(s, isNot(contains('1 to 3 sentences')));
    expect(s, contains('There is no cap'));
  });

  test('the no-dash rule survives', () {
    final m = builder.build(
      context: ctx(),
      history: const [],
      userMessage: 'anything',
    );
    expect(systemText(m), contains('NEVER use an em dash'));
  });
}
