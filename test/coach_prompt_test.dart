import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/coach_prompt_builder.dart';
import 'package:ourmynd/models/chat_message.dart';
import 'package:ourmynd/models/coach_context.dart';

/// The coach's memory should arrive when the turn is about them, and stay out
/// of the way when it is not.
void main() {
  _agentAndMailPrompt();
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

/// The two things that grew the system prompt: the agent persona and the email
/// instructions. Both were added the same afternoon a turn started failing with
/// "Something went wrong on my end", so both get pinned here.
///
/// The build is pure and synchronous, which is exactly where that failure was
/// coming from: an exception thrown while assembling the prompt lands in the
/// same catch as a network error and reads identically to one.
void _agentAndMailPrompt() {
  final builder = CoachPromptBuilder.instance;

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

  group('agent and mail blocks', () {
    test('building with an agent block does not throw', () {
      final m = builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'i am overwhelmed',
        agentBlock: 'YOU ARE BLITZ\nBlunt, fast, impatient with circling.',
      );
      expect(m, isNotEmpty);
      expect(
        m.where((x) => x['role'] == 'system').length,
        greaterThanOrEqualTo(2),
        reason: 'the persona is its own system message, after the base one',
      );
      expect(m.last['content'], 'i am overwhelmed');
    });

    test('the persona comes after the house voice, so it wins', () {
      final m = builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'hi',
        agentBlock: 'YOU ARE BLITZ',
      );
      final systems = m.where((x) => x['role'] == 'system').toList();
      expect(systems.first['content'], contains('SYSTEM ROLE'));
      expect(systems[1]['content'], contains('YOU ARE BLITZ'));
    });

    test('both mail states build, and say opposite things', () {
      final off = builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'email sam',
      ).first['content']!;
      final on = builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'email sam',
        mailConnected: true,
      ).first['content']!;

      expect(off, contains('You cannot send email'));
      expect(on, contains('[[email:'));
      expect(on, isNot(contains('You cannot send email')));
    });

    test('sending is the default once an account is connected', () {
      // The complaint that produced this: "i connected, but it still says i
      // can only draft". Half of that was a genuinely unconnected account,
      // and half was a prompt that hedged hard enough for the model to offer
      // a draft anyway.
      final on = builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'send sam an email saying i will be late',
        mailConnected: true,
      ).first['content']!;

      expect(on, contains('Sending is the default'));
      expect(on, isNot(contains('Send immediately only when')));
    });

    test('an account that can send but not read says so', () {
      // Reading is a Google restricted scope and sending is not, so this is a
      // state real accounts land in rather than a hypothetical. A coach that
      // claims to read an inbox it has no permission for looks broken in a
      // way nobody can diagnose from the outside.
      final sendOnly = builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'what is in my inbox',
        mailConnected: true,
      ).first['content']!;
      final both = builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'what is in my inbox',
        mailConnected: true,
        mailCanRead: true,
      ).first['content']!;

      expect(sendOnly, contains('cannot read their inbox'));
      expect(sendOnly, contains('[[email:'),
          reason: 'it can still send, and must still be told how');
      expect(both, contains('You can also READ their recent mail'));
      expect(both, isNot(contains('cannot read their inbox')));
    });

    test('no message exceeds what the server will accept', () {
      // The route caps content at 24,000 characters and the array at 60. A
      // prompt that grew past either would be rejected with a 400 that reaches
      // the user as a generic failure.
      final m = builder.build(
        context: plain(),
        history: const <ChatMessage>[],
        userMessage: 'hello',
        agentBlock: 'YOU ARE SPROUT\n' * 20,
        mailConnected: true,
      );
      expect(m.length, lessThanOrEqualTo(60));
      for (final msg in m) {
        expect(msg['content']!.length, lessThanOrEqualTo(24000));
        expect(msg['role'], isIn(const ['system', 'user', 'assistant']));
      }
    });
  });
}
