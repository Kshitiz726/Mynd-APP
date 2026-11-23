import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app's own work must not be rationed by the coach's daily cap.
///
/// This is a source scan rather than a behavioural test on purpose. The bug it
/// guards against is invisible at runtime until somebody has spent five
/// messages: every caller of the metered route treats a refusal as "leave it as
/// it was", so a goal created on a spent day just quietly had no plan. Nothing
/// fails, nothing logs, and the feature looks broken rather than capped. A test
/// that has to burn a real quota to notice would never be run.
///
/// If a new feature genuinely is a conversation with the coach, metering it is
/// correct - add it to [conversational] below and say why.
void main() {
  /// Call sites allowed to spend a coaching message.
  ///
  /// One entry, and it is the real conversation. The coach no longer runs on
  /// Puter: a live turn goes through [AiRouter], which picks the provider and
  /// falls back to the built-in Groq backend. That backend is the metered
  /// route, and metering it is the entire point, because that turn is the user
  /// talking to the coach.
  ///
  /// Everything else in the app must stay off it. The feed, goals, mood,
  /// memory, soul and brain dump all go to GroqService.extract on the
  /// unmetered route, and they must keep doing so even though the chat has
  /// moved: a provider migration is exactly the kind of change that quietly
  /// drags internal calls onto the user's quota.
  const conversational = <String>{
    'lib/core/services/ai/ai_router.dart:20',
  };

  test("the app's own work does not go through the metered coach route", () {
    final offenders = <String>[];

    for (final file in Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('GroqService.instance.complete(') &&
            !lines[i].contains('GroqService.instance.streamCompletion(')) {
          continue;
        }
        final where = '${file.path}:${i + 1}';
        if (conversational.contains(where)) continue;
        offenders.add(where);
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These spend one of the five free daily coaching messages.\n'
          'Brain dumps, goal plans, task breakdowns, mood guesses and memory\n'
          'rewrites are the app talking to itself, not the user talking to the\n'
          'coach - they belong on GroqService.extract, which is unmetered.\n'
          'Offenders:\n  ${offenders.join('\n  ')}',
    );
  });

  test('the unmetered route is the one the brain dump and goals use', () {
    String read(String p) => File(p).readAsStringSync();

    expect(
      read('lib/features/home/widgets/brain_dump_sheet.dart'),
      contains('GroqService.instance.extract('),
      reason: 'typed and spoken brain dumps share this call',
    );
    expect(
      read('lib/providers/goal_provider.dart'),
      contains("task: 'plan'"),
      reason: 'a goal plan needs the larger ceiling, or its JSON is truncated',
    );
    // The server, not the client, decides what a task costs. If this moves to
    // the request body, an unmetered route becomes a free proxy for our key.
    expect(
      read('server/src/routes/coach.ts'),
      contains('EXTRACT_CEILING[parsed.data.task]'),
    );
  });
}
