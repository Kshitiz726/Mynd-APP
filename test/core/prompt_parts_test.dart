import 'package:flutter_test/flutter_test.dart';
import 'package:ourmynd/core/services/ai/prompt_parts.dart';

/// Translating the prompt for Claude and Gemini.
///
/// The coach's whole personality, and every feature that works by asking the
/// model to emit a marker ([[remind: ...]], [[email: ...]]), rides in the
/// system messages the prompt builder produces. If this translation drops one,
/// reorders them, or mangles the turns, the symptom is not a crash: it is a
/// coach that quietly stops setting reminders, or stops sounding like itself.
/// So the rules are pinned here rather than left to a reading of the code.
void main() {
  mainRealWorldShape();
  Map<String, String> m(String role, String content) =>
      {'role': role, 'content': content};

  group('system messages', () {
    test('all of them survive, in order', () {
      // Order is precedence: the agent persona is written to contradict the
      // house voice, and the model reads the later instruction as the winner.
      final p = PromptParts.from([
        m('system', 'identity'),
        m('system', 'agent persona'),
        m('system', 'memory'),
        m('user', 'hi'),
      ]);
      expect(p.system, 'identity\n\nagent persona\n\nmemory');
    });

    test('no system messages gives an empty instruction, not a crash', () {
      final p = PromptParts.from([m('user', 'hi')]);
      expect(p.system, isEmpty);
      expect(p.turns, [const PromptTurn('user', 'hi')]);
    });

    test('a system message after the conversation still counts', () {
      // The builder puts context notes before history today, but nothing in
      // the translation should depend on that.
      final p = PromptParts.from([
        m('user', 'hi'),
        m('system', 'late context'),
      ]);
      expect(p.system, 'late context');
      expect(p.turns.length, 1);
    });
  });

  group('turns', () {
    test('alternating turns pass through untouched', () {
      final p = PromptParts.from([
        m('system', 's'),
        m('user', 'one'),
        m('assistant', 'two'),
        m('user', 'three'),
      ]);
      expect(p.turns, const [
        PromptTurn('user', 'one'),
        PromptTurn('assistant', 'two'),
        PromptTurn('user', 'three'),
      ]);
    });

    test('two user turns in a row are merged, not sent as two', () {
      // Anthropic rejects consecutive same-role turns outright. A retry or a
      // trimmed history can produce them, and a hard API error in the middle
      // of somebody's conversation is worse than merging.
      final p = PromptParts.from([
        m('user', 'first'),
        m('user', 'second'),
      ]);
      expect(p.turns, const [PromptTurn('user', 'first\n\nsecond')]);
    });

    test('two assistant turns in a row are merged too', () {
      final p = PromptParts.from([
        m('user', 'q'),
        m('assistant', 'a'),
        m('assistant', 'b'),
      ]);
      expect(p.turns, const [
        PromptTurn('user', 'q'),
        PromptTurn('assistant', 'a\n\nb'),
      ]);
    });

    test('a leading assistant turn is dropped so the user speaks first', () {
      final p = PromptParts.from([
        m('assistant', 'dangling half of a trimmed exchange'),
        m('user', 'hello'),
      ]);
      expect(p.turns, const [PromptTurn('user', 'hello')]);
    });

    test('empty content is skipped rather than sent', () {
      // A streaming placeholder that never filled would otherwise become an
      // empty assistant turn, which some providers reject.
      final p = PromptParts.from([
        m('user', 'hi'),
        m('assistant', ''),
        m('user', 'still there?'),
      ]);
      expect(p.turns, const [PromptTurn('user', 'hi\n\nstill there?')]);
    });

    test('an unknown role is kept as the user rather than dropped', () {
      // Losing what somebody typed is the worst available outcome.
      final p = PromptParts.from([m('tool', 'something')]);
      expect(p.turns, const [PromptTurn('user', 'something')]);
    });
  });

  test('a realistic coach prompt translates whole', () {
    final p = PromptParts.from([
      m('system', 'SYSTEM ROLE ...'),
      m('system', 'AGENT: Blitz ...'),
      m('system', 'MEMORY ...'),
      m('system', 'THEIR DAY ...'),
      m('user', 'i cant start'),
      m('assistant', 'yeah, that one is horrible'),
      m('user', 'remind me at 8'),
    ]);
    expect(p.system.split('\n\n').length, 4,
        reason: 'all four system blocks must reach the model');
    expect(p.turns.length, 3);
    expect(p.turns.first.role, 'user');
    expect(p.turns.last.text, 'remind me at 8');
  });
}

/// The shape that actually broke Claude and Gemini in the app.
///
/// CoachPromptBuilder emits a leading system message, and when a turn touches
/// mail or the calendar CoachProvider inserts a SECOND system message
/// immediately before the user's line. Groq is OpenAI-compatible and accepts
/// that, so it was never noticed. Anthropic has no system role in the messages
/// array and Gemini has none in `contents`, so for those two the turn was
/// rejected and no reply ever came back: "connected, but the chat does
/// nothing".
///
/// PromptParts was written for this and then left unwired, which is the part
/// worth remembering. These assert the real payload rather than a tidy one.
void mainRealWorldShape() {
  group('the real coach payload', () {
    test('two system messages become one, in order', () {
      final parts = PromptParts.from([
        {'role': 'system', 'content': 'house voice'},
        {'role': 'user', 'content': 'hello'},
        {'role': 'assistant', 'content': 'hi'},
        // The mail and calendar block, inserted before the latest user line.
        {'role': 'system', 'content': 'inbox context'},
        {'role': 'user', 'content': 'what did Sam send me'},
      ]);

      expect(parts.system, 'house voice\n\ninbox context',
          reason: 'order carries precedence: later instructions win');
      expect(parts.turns.map((t) => t.role).toList(),
          ['user', 'assistant', 'user']);
      expect(parts.turns.last.text, 'what did Sam send me',
          reason: 'the system block must not be glued onto the user turn');
    });

    test('no system message anywhere leaves the system block empty', () {
      final parts = PromptParts.from([
        {'role': 'user', 'content': 'hello'},
      ]);
      expect(parts.system, isEmpty,
          reason: 'the backend omits the system entry entirely in that case');
      expect(parts.turns, hasLength(1));
    });
  });
}
