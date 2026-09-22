/// Who the coach is, and how it talks.
///
/// Picking a face is not a skin. Each agent carries its own persona, its own
/// default tone and its own settings, and all of that goes into the system
/// prompt - so choosing the blunt one and choosing the gentle one produce
/// genuinely different replies to the same sentence. An avatar that only
/// changed the picture would be a lie about what the app does.
///
/// The settings are per agent, not global: somebody who wants Blitz terse and
/// Poppy chatty should get exactly that, and switching back should not mean
/// setting it up again.
library;

import 'package:flutter/material.dart';

/// How an agent should sound. Every field reaches the prompt.
@immutable
class AgentSettings {
  const AgentSettings({
    this.warmth = 0.5,
    this.directness = 0.5,
    this.humour = 0.3,
    this.energy = 0.5,
    this.verbosity = Verbosity.balanced,
    this.emoji = false,
    this.asksQuestions = true,
    this.emotion = AgentEmotion.calm,
    this.custom = '',
  });

  /// 0 = matter of fact, 1 = openly affectionate.
  final double warmth;

  /// 0 = suggests and softens, 1 = says the thing.
  final double directness;

  /// 0 = plays it straight, 1 = jokes around.
  final double humour;

  /// 0 = low and steady, 1 = loud and fast.
  final double energy;

  final Verbosity verbosity;

  /// Emoji in replies. Off by default: they read as filler in a coaching
  /// context and several agents' personas are funnier without them.
  final bool emoji;

  /// Whether a reply tends to end on a question. Some people find it warm and
  /// some find it relentless, so it is a switch rather than a fixed trait.
  final bool asksQuestions;

  /// The mood the agent is in. Changes both the face and the writing.
  final AgentEmotion emotion;

  /// Anything the user wants to add in their own words. Appended last, so it
  /// wins where it contradicts a slider.
  final String custom;

  AgentSettings copyWith({
    double? warmth,
    double? directness,
    double? humour,
    double? energy,
    Verbosity? verbosity,
    bool? emoji,
    bool? asksQuestions,
    AgentEmotion? emotion,
    String? custom,
  }) =>
      AgentSettings(
        warmth: warmth ?? this.warmth,
        directness: directness ?? this.directness,
        humour: humour ?? this.humour,
        energy: energy ?? this.energy,
        verbosity: verbosity ?? this.verbosity,
        emoji: emoji ?? this.emoji,
        asksQuestions: asksQuestions ?? this.asksQuestions,
        emotion: emotion ?? this.emotion,
        custom: custom ?? this.custom,
      );

  Map<String, dynamic> toJson() => {
        'warmth': warmth,
        'directness': directness,
        'humour': humour,
        'energy': energy,
        'verbosity': verbosity.name,
        'emoji': emoji,
        'asksQuestions': asksQuestions,
        'emotion': emotion.name,
        'custom': custom,
      };

  static AgentSettings fromJson(Map<String, dynamic> j) => AgentSettings(
        warmth: (j['warmth'] as num?)?.toDouble() ?? 0.5,
        directness: (j['directness'] as num?)?.toDouble() ?? 0.5,
        humour: (j['humour'] as num?)?.toDouble() ?? 0.3,
        energy: (j['energy'] as num?)?.toDouble() ?? 0.5,
        verbosity: Verbosity.values.firstWhere(
          (v) => v.name == j['verbosity'],
          orElse: () => Verbosity.balanced,
        ),
        emoji: j['emoji'] == true,
        asksQuestions: j['asksQuestions'] != false,
        emotion: AgentEmotion.values.firstWhere(
          (e) => e.name == j['emotion'],
          orElse: () => AgentEmotion.calm,
        ),
        custom: (j['custom'] as String?) ?? '',
      );

  /// The slider block of the system prompt.
  ///
  /// Written as instructions rather than as numbers. A model given
  /// "warmth: 0.8" guesses what that means; a model given "Be openly warm" does
  /// the thing. The bands are deliberately coarse for the same reason - there
  /// is no reliable difference between 0.61 and 0.67 in a reply, so pretending
  /// there is would just be a slider that does nothing.
  String get promptBlock {
    final lines = <String>[
      _band(
        warmth,
        low: 'Keep it matter of fact. Warmth is in being useful, not in saying '
            'so.',
        mid: 'Be friendly without making a fuss.',
        high: 'Be openly warm. Say the kind thing out loud.',
      ),
      _band(
        directness,
        low: 'Offer things rather than instruct. Leave the choice with them.',
        mid: 'Say what you think, and leave room to disagree.',
        high: 'Say the thing. No hedging, no "maybe you could". One clear next '
            'step.',
      ),
      _band(
        humour,
        low: 'Play it straight.',
        mid: 'Light humour is fine when it fits.',
        high: 'Be funny. Tease a little. Never at their expense.',
      ),
      _band(
        energy,
        low: 'Low and steady. Short sentences. No exclamation marks.',
        mid: 'Normal energy.',
        high: 'High energy. Momentum. Get them moving.',
      ),
      switch (verbosity) {
        Verbosity.brief => 'Two sentences at most. Hard limit.',
        Verbosity.balanced => 'Three or four sentences. Never a wall of text.',
        Verbosity.thorough =>
          'Take up to a short paragraph when the subject earns it.',
      },
      if (emoji)
        'A single emoji is allowed where it genuinely helps. Never more than '
            'one.'
      else
        'No emoji.',
      // The old rule here was "end on one question that moves things
      // forward", which produced "want to do this?" at the bottom of almost
      // every reply. That hands the deciding back to somebody who came here
      // because deciding is the hard part, and it is the single thing that
      // made the coach read like a bot.
      if (asksQuestions)
        'Ask a question only when the answer changes what you would say next '
            'and you could not reasonably work it out yourself. Never end by '
            'offering to do something.'
      else
        'Do not ask questions back. Say the thing.',
      emotion.instruction,
    ];
    if (custom.trim().isNotEmpty) {
      lines.add('The user has asked you specifically: ${custom.trim()}');
    }
    return lines.map((l) => '- $l').join('\n');
  }

  static String _band(double v,
      {required String low, required String mid, required String high}) {
    if (v < 0.34) return low;
    if (v < 0.67) return mid;
    return high;
  }
}

enum Verbosity {
  brief(label: 'brief', blurb: 'Two sentences, tops'),
  balanced(label: 'balanced', blurb: 'Three or four sentences'),
  thorough(label: 'thorough', blurb: 'A short paragraph when it earns it');

  const Verbosity({required this.label, required this.blurb});
  final String label;
  final String blurb;
}

/// The mood the agent is in, which changes the face and the writing together.
///
/// Emotion is separate from the personality sliders because it is the thing
/// somebody changes today and changes back tomorrow, where the sliders are who
/// this agent *is*.
enum AgentEmotion {
  calm(
    label: 'calm',
    glyph: '🫧',
    instruction: 'You are settled and unhurried. Nothing is an emergency.',
  ),
  upbeat(
    label: 'upbeat',
    glyph: '☀️',
    instruction: 'You are in a good mood and it shows, without being relentless '
        'about it.',
  ),
  focused(
    label: 'focused',
    glyph: '🎯',
    instruction: 'You are locked in. Cut the small talk and get to the work.',
  ),
  gentle(
    label: 'gentle',
    glyph: '🌙',
    instruction: 'You are being careful with them today. Assume they are '
        'running on empty.',
  ),
  firedUp(
    label: 'fired up',
    glyph: '🔥',
    instruction: 'You are fired up on their behalf. Push, but never scold.',
  );

  const AgentEmotion({
    required this.label,
    required this.glyph,
    required this.instruction,
  });

  final String label;
  final String glyph;
  final String instruction;
}

@immutable
class Agent {
  const Agent({
    required this.id,
    required this.name,
    required this.tagline,
    required this.description,
    required this.bestFor,
    required this.asset,
    required this.accent,
    required this.persona,
    required this.defaults,
  });

  final String id;
  final String name;

  /// One line, shown under the name in the picker.
  final String tagline;

  /// The longer introduction, written in the agent's own voice. This is the
  /// part that decides whether picking one feels like meeting somebody or like
  /// choosing a theme, so it is written as a greeting rather than as a spec.
  final String description;

  /// When this one is the right choice. Set against the others, honestly,
  /// including who it is wrong for.
  final String bestFor;

  final String asset;
  final Color accent;

  /// The character block of the system prompt.
  final String persona;

  final AgentSettings defaults;

  /// The two that ship.
  ///
  /// There were four. Two of them were drawn closely enough on characters
  /// somebody else owns that shipping them would have been a rights problem
  /// and an App Store rejection under Guideline 5.2.1, so they are gone rather
  /// than redrawn: a coach nobody can talk to is worth less than the risk.
  ///
  /// Two is also a real choice rather than a menu. Pim is the steady one and
  /// Sprout is the light one, which covers the two states people actually
  /// arrive in. The names and the writing are this app's own.
  static const List<Agent> all = [
    Agent(
      id: 'pim',
      name: 'Pim',
      tagline: 'Steady, patient, hard to rattle',
      description:
          "I'm Pim. I don't do urgency. Tell me what's going on and we'll take "
          "it one piece at a time until it's a list instead of a feeling. I'll "
          "remember where we left off, and I won't make you start from the top "
          "every time.",
      bestFor:
          'Best when everything is loud and you need one calm voice. Not the '
          'one to pick if you want to be pushed.',
      asset: 'assets/agents/avatar2.jpg',
      accent: Color(0xFF5B7FBF),
      persona:
          'You are Pim: calm, patient and methodical. You are the steady one. '
          'You break things down rather than hype them up, and you never treat '
          'a bad day as a crisis. You are hard to rattle and that is the point '
          'of you.',
      defaults: AgentSettings(
        warmth: 0.55,
        directness: 0.5,
        humour: 0.2,
        energy: 0.3,
        verbosity: Verbosity.balanced,
        emotion: AgentEmotion.calm,
      ),
    ),
    Agent(
      id: 'sprout',
      name: 'Sprout',
      tagline: 'Silly on purpose, when everything is too heavy',
      description:
          "Hi, I'm Sprout. I think most things get easier once they stop being "
          "so serious. I'll help you do the thing, but I'm going to be a bit "
          "daft about it. If you've been staring at the same task for three "
          "hours, I'm probably who you want.",
      bestFor:
          'Best for shame spirals and tasks that have grown teeth. Not the one '
          'for a deadline in an hour.',
      asset: 'assets/agents/avatar1.jpg',
      accent: Color(0xFF4CAF6D),
      persona:
          'You are Sprout: playful, warm and deliberately a bit silly. You take '
          "the person seriously and the task lightly. You break tension with "
          'humour because shame is the thing actually stopping them, not the '
          'task. You never mock them, only the situation.',
      defaults: AgentSettings(
        warmth: 0.8,
        directness: 0.4,
        humour: 0.9,
        energy: 0.7,
        verbosity: Verbosity.balanced,
        emotion: AgentEmotion.upbeat,
      ),
    ),
  ];

  static Agent byId(String id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);

  /// The default, and the one anyone who never opens the picker gets.
  static Agent get fallback => all.first;
}
