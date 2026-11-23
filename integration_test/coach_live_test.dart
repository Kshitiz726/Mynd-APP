import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ourmynd/core/services/api_client.dart';
import 'package:ourmynd/core/services/coach_prompt_builder.dart';
import 'package:ourmynd/core/services/groq_service.dart';
import 'package:ourmynd/core/services/session_store.dart';
import 'package:ourmynd/models/agent.dart';
import 'package:ourmynd/models/chat_message.dart';
import 'package:ourmynd/models/coach_context.dart';

/// Does the coach actually answer?
///
/// Every other test in this repo mocks the round trip, and every one of them
/// passed on the afternoon the chat was completely broken. The failure was a
/// week key written into a DATE column: the TypeScript compiled, the widget
/// tests were green, the prompt builder was provably fine, and every single
/// call to the meter answered HTTP 500. Nothing that stops at the edge of the
/// network could have caught it.
///
/// So this one goes the whole way: a session out of the keychain, the meter on
/// Render, Postgres behind it, and Groq behind that. It asserts on a reply with
/// words in it, because "no exception was thrown" is not the same thing as the
/// coach having said something - an empty reply is exactly what a reasoning
/// model returns when its token budget goes entirely on thinking.
///
/// Needs a device with a signed-in session. It says so rather than passing
/// quietly if there is none: a green run that proved nothing is worse than a
/// red one.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the coach answers a real turn against the live server',
      (tester) async {
    final restored = await SessionStore.restore();
    expect(restored, isTrue,
        reason: 'no session on this device - sign in first, or this test '
            'proves nothing');

    final api = ApiClient.instance;

    // ── 1. The meter reads back ──
    //
    // This is the call that was returning 500. Asserted on its own so a
    // failure here says "the meter is broken" rather than being swallowed into
    // a general "the chat does not work".
    final quota = await api.coachQuota();
    debugPrint('[e2e] quota: $quota');
    expect(quota['limit'], isNotNull,
        reason: 'the server did not report a weekly limit');
    final limit = quota['limit'] as int;
    final used = quota['used'] as int? ?? 0;
    final remaining = quota['remaining'] as int? ?? 0;
    expect(limit, greaterThanOrEqualTo(100),
        reason: 'the weekly free allowance should be at least 100');
    expect(quota['resetsAt'], isNotNull,
        reason: 'the app tells the user when the allowance comes back');
    debugPrint('[e2e] $used of $limit used, $remaining left this week');

    if (remaining <= 0) {
      fail('this account has no messages left this week, so a reply cannot '
          'be proved. Wait for the reset or raise the limit.');
    }

    // ── 2. A turn is granted ──
    final turn = await api.spendCoachTurn();
    debugPrint('[e2e] turn granted: remaining=${turn.remaining} '
        'used=${turn.used} limit=${turn.limit}');
    expect(turn.remaining, isNotNull);

    // ── 3. The model actually says something ──
    //
    // Built through the real prompt builder, with a real agent persona, so the
    // thing under test is the prompt the app genuinely sends rather than a
    // convenient short one.
    const ctx = CoachContext(
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

    final agent = Agent.byId('pim');
    final messages = CoachPromptBuilder.instance.build(
      context: ctx,
      history: const <ChatMessage>[],
      userMessage: "i'm overwhelmed",
      agentBlock: 'YOU ARE ${agent.name.toUpperCase()}\n${agent.persona}',
    );
    debugPrint('[e2e] prompt: ${messages.length} messages, '
        '${messages.fold<int>(0, (n, m) => n + m['content']!.length)} chars');

    final buffer = StringBuffer();
    await for (final chunk
        in GroqService.instance.streamCompletion(messages)) {
      buffer.write(chunk);
    }
    final reply = buffer.toString().trim();
    debugPrint('[e2e] reply (${reply.length} chars): $reply');

    expect(reply, isNotEmpty,
        reason: 'the stream completed with no content at all - the token '
            'budget went entirely on reasoning');
    expect(reply.split(RegExp(r'\s+')).length, greaterThanOrEqualTo(3),
        reason: 'a reply of one or two words is not an answer');

    // The house style, checked on a real reply rather than only in the prompt.
    expect(reply.contains('—'), isFalse, reason: 'an em dash got through');
    expect(reply.contains('–'), isFalse, reason: 'an en dash got through');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
