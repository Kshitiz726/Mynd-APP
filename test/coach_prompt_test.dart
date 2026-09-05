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

  CoachContext withMood(List<MoodLogEntry> logs) => CoachContext(
        userName: 'sam',
        currentEnergyLevel: 'low',
        recentMoodLogs: logs,
        recentBrainDumps: const [],
        todayTasks: const [
          TaskSummary(
              title: 'file the tax return', energyLevel: 'high', isDone: false),
        ],
        habitProgress: const HabitProgress(
            completedToday: 0,
            totalHabits: 0,
            longestStreakName: null,
            longestStreakDays: 0),
        focusStatistics: const FocusStatistics(
            sessionsToday: 0, minutesFocusedToday: 0, currentStreakDays: 0),
        previousConversationSummary: '',
        userPreferences: const CoachUserPreferences(),
        detectedPatterns: const [],
      );

  MoodLogEntry mood(String m, {int daysAgo = 0, String? note}) => MoodLogEntry(
        mood: m,
        intensity: 3,
        loggedAt: DateTime(2026, 9, 1).subtract(Duration(days: daysAgo)),
        note: note,
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

  // ─── The mood has to actually change the instruction ──────────────────────
  //
  // recentMoodLogs was populated but never rendered, so the one control the
  // user sets by hand reached the model as nothing at all.

  group('the mood reaches the model as an instruction', () {
    test('a rough day is told to drop the task talk', () {
      final m = builder.build(
        context: withMood([mood('rough')]),
        history: const [],
        userMessage: 'what should i do with my day',
      );
      final text = systemText(m);
      expect(text, contains('MOOD'));
      expect(text, contains('rough'));
      expect(text, contains('Drop the task talk'));
    });

    test('a great day gets the opposite instruction', () {
      final text = systemText(builder.build(
        context: withMood([mood('great')]),
        history: const [],
        userMessage: 'what should i do with my day',
      ));
      expect(text, contains('Meet the energy'));
      expect(text, isNot(contains('Drop the task talk')));
    });

    test('a run of bad days is named as a run', () {
      final text = systemText(builder.build(
        context: withMood([
          mood('rough'),
          mood('low', daysAgo: 1),
          mood('rough', daysAgo: 2),
        ]),
        history: const [],
        userMessage: 'how is my week going',
      ));
      expect(text, contains('Weigh the run'));
      expect(text, contains('rough then low then rough'));
    });

    test('their own words outrank the rating', () {
      final text = systemText(builder.build(
        context: withMood([mood('okay', note: 'dreading the call at 4')]),
        history: const [],
        userMessage: 'what should i do with my day',
      ));
      expect(text, contains('dreading the call at 4'));
      expect(text, contains('matters more than the rating'));
    });

    test('no check-in means no mood block at all', () {
      // Silence is not "okay". Inventing a middling mood for somebody who has
      // not said anything is a claim, and a wrong one.
      final text = systemText(builder.build(
        context: withMood(const []),
        history: const [],
        userMessage: 'what should i do with my day',
      ));
      expect(text, isNot(contains('MOOD:')));
    });

    test('a general question still carries no mood', () {
      final text = systemText(builder.build(
        context: withMood([mood('rough')]),
        history: const [],
        userMessage: 'explain how a diesel engine differs from a petrol one',
      ));
      expect(text, isNot(contains('MOOD:')));
    });
  });
}
