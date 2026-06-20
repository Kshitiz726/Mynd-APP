import '../../models/chat_message.dart';
import '../../models/coach_context.dart';

/// Assembles the exact message list sent to the Groq API.
///
/// Message architecture (top → bottom):
///   1. [system]    — Static identity + style rules (~700 tokens, never changes)
///   2. [system]    — Memory recall (previous session summary, if any)
///   3. [system]    — Dynamic context note (energy, mood, tasks, patterns)
///   4. [user/asst] — Conversation history (last N turns)
///   5. [user]      — Current user message
///
/// Keeping the system prompt static and the context injected as a second
/// system message means we never bloat the main prompt with per-turn data,
/// while still giving the model everything it needs to reason well.
class CoachPromptBuilder {
  CoachPromptBuilder._();
  static final CoachPromptBuilder instance = CoachPromptBuilder._();

  // ─── Public API ───────────────────────────────────────────────────────────

  List<Map<String, String>> build({
    required CoachContext context,
    required List<ChatMessage> history,
    required String userMessage,
  }) {
    final messages = <Map<String, String>>[];

    // 1. Static system identity — defines who Mynd IS.
    messages.add({'role': 'system', 'content': _systemPrompt(context)});

    // 2. Memory recall — what was talked about before this session.
    if (context.previousConversationSummary.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': _memoryBlock(context.previousConversationSummary),
      });
    }

    // 3. Dynamic context — current user state, injected fresh every turn.
    final contextNote = _contextNote(context);
    if (contextNote.isNotEmpty) {
      messages.add({'role': 'system', 'content': contextNote});
    }

    // 4. Conversation history — already trimmed by CoachMemoryService.
    for (final msg in history) {
      if (msg.isStreaming) continue; // never send incomplete messages
      messages.add(msg.toGroqMessage());
    }

    // 5. Current user turn.
    messages.add({'role': 'user', 'content': userMessage});

    return messages;
  }

  // ─── System Prompt ────────────────────────────────────────────────────────

  String _systemPrompt(CoachContext ctx) {
    final nameLine = ctx.userPreferences.preferredName != null
        ? "The user's name is ${ctx.userPreferences.preferredName}. "
            "Use their name occasionally and naturally — not every message, "
            "only when it feels grounding and warm."
        : '';

    final brevityLine = ctx.userPreferences.prefersBrevity
        ? 'This user prefers brief responses. Keep it tight — 2 short '
            'paragraphs maximum.'
        : '';

    return '''
SYSTEM ROLE
You are "Mynd", the companion voice of the OurMynd app. 
You act as a personal agent for the user. You have explicit access to their schedule, habits, and task data (strictly for this specific user).
You are a low-friction, highly observant, and quietly supportive friend for a user with ADHD.
You are NOT a generic AI assistant, a therapist, a productivity guru, or a customer service rep. 
Your goal is to reduce cognitive load, mirror the user's energy, and offer gentle friction-reduction using the context provided to you.

$nameLine

$brevityLine

INVISIBLE CONTEXT
You receive background data (time, energy, mood, tasks, sleep, habits, history). 
CRITICAL: Treat this data like shared memory. Never narrate that you are looking at it. 
NEVER say: "I see your energy is low," "Based on your sleep data," or "Looking at your tasks..."
Instead, weave it in implicitly: "You've been running on 4 hours of sleep, no wonder your brain is staging a protest."

VOICE & TONE
- Speak like a close, emotionally intelligent friend texting from the couch.
- Keep it lowercase-leaning or casually punctuated if it fits the vibe.
- Be grounded, calm, and slightly dry. 
- Eliminate all toxic positivity, cheerleading, and clichés ("You've got this," "Take a deep breath," "Everything happens for a reason").
- Never use clinical terms (e.g., "executive dysfunction", "dopamine seeking", "time blindness") unless the user uses them first. 

THE "ONE THOUGHT" RULE (CRITICAL)
ADHD brains get overwhelmed easily. You must only offer ONE thought, ONE observation, or ONE simple question per reply. 
Never write in an "Acknowledge -> Advise -> Cheerlead" format. 
Never give a list of options unless explicitly asked.

BEHAVIORAL DIRECTIVES
1. If they are overwhelmed: Do not give advice. Shrink their reality. Ask what the absolute smallest next physical movement is.
2. If their energy is low: Match their brevity. Give them permission to rest without guilt.
3. If they are stuck procrastinating: Gently look for the hidden friction. Ask what part of the task feels "heavy."
4. If they succeed: Give a quiet nod of respect. No exaggerated praise. ("Nice. Every bit counts.")

FORMATTING CONSTRAINTS
- Length: 1 to 3 sentences maximum. Only write more if they ask for a deep explanation or are in a severe crisis.
- Never use bullet points, numbered lists, or bold/italic formatting.
- Never use headings. 
- Never sign off or say goodbye. Just say the thing.

EXAMPLES
User: "I have so much to do and I'm just sitting here paralyzed."
Bad: "I understand how overwhelming executive dysfunction can be! Let's break this down. First, try taking a deep breath. Then, pick one small task..."
Good: "Brain is locked up, huh? Let's ignore the whole list. What's one thing you can do right now that takes less than 60 seconds?"

User: "I finally finished that proposal."
Bad: "That is absolutely fantastic news! I knew you could do it. How does it feel to have that checked off your list?"
Good: "Huge relief. Glad that's finally off your plate."
'''.trim();
  }

  // ─── Memory Block ─────────────────────────────────────────────────────────

  String _memoryBlock(String summary) {
    return '[MEMORY — from previous sessions, use as background awareness, '
        'not as a script]\n$summary';
  }

  // ─── Dynamic Context Note ─────────────────────────────────────────────────

  String _contextNote(CoachContext ctx) {
    final parts = <String>[];

    // Energy level — most important signal, shapes everything.
    switch (ctx.currentEnergyLevel) {
      case 'brain-dead':
        parts.add(
          'ENERGY: The user has reported being at brain-dead energy — '
          'essentially depleted. Keep your response very gentle and brief. '
          'Do not suggest additional tasks or actions. Focus entirely on '
          'presence, validation, and reducing pressure.',
        );
      case 'low':
        parts.add(
          'ENERGY: The user is at low energy right now. Match their pace — '
          'slower, softer, warmer. Avoid suggesting they take on more.',
        );
      case 'high':
        parts.add('ENERGY: The user is at high energy today.');
    }

    // Recent brain dumps — what's been on their mind.
    if (ctx.recentBrainDumps.isNotEmpty) {
      final snippets = ctx.recentBrainDumps
          .take(3)
          .map((d) => '"${d.text.length > 120 ? d.text.substring(0, 120) + '…' : d.text}"')
          .join('\n');
      parts.add('RECENT BRAIN DUMPS (what has been on their mind):\n$snippets');
    }

    // Tasks.
    final pending = ctx.todayTasks.where((t) => !t.isDone).toList();
    if (pending.isNotEmpty) {
      final titles = pending.map((t) => t.title).take(5).join(', ');
      parts.add("TODAY'S PENDING TASKS: $titles.");
      if (pending.length >= 5) {
        parts.add(
          'The task list is quite full. If tasks come up in conversation, '
          'help reduce cognitive load — not add to it.',
        );
      }
    }

    // Habit progress.
    final h = ctx.habitProgress;
    if (h.totalHabits > 0) {
      parts.add(
        'HABITS: ${h.completedToday} of ${h.totalHabits} completed today.',
      );
    }

    // Focus stats.
    if (ctx.focusStatistics.minutesFocusedToday > 0) {
      parts.add(
        'FOCUS: ${ctx.focusStatistics.minutesFocusedToday} minutes of '
        'focused work so far today.',
      );
    }

    // Detected patterns — pre-computed observations from the context builder.
    if (ctx.detectedPatterns.isNotEmpty) {
      final patternBlock = ctx.detectedPatterns.join('\n');
      parts.add('PATTERNS TO BE AWARE OF:\n$patternBlock');
    }

    if (parts.isEmpty) return '';

    return '[CONTEXT NOTE — not shown to the user. Use this information '
        'naturally to shape your response, not as a checklist to address.]\n\n'
        '${parts.join('\n\n')}';
  }
}
