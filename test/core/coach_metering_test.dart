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
  /// Empty today, and that is the honest state of the app: the live coach runs
  /// on Puter, so nothing in here talks to the metered route at all.
  const conversational = <String>{};

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
