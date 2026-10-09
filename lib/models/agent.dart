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

  /// The three that ship.
  ///
  /// There were four, then two. The original four were drawn closely enough on
  /// characters somebody else owns that shipping them would have been a rights
  /// problem and an App Store rejection under Guideline 5.2.1, so they went
  /// rather than being redrawn. These three are this app's own artwork.
  ///
  /// Three because they are three answers to "what state did you arrive in",
  /// not three skins. Ember is for when there is momentum to spend, Hush is
  /// for when there is too much noise, and Wren is for when something is
  /// genuinely worrying you. Each one's face is the mood it writes in, and the
  /// persona below is what actually reaches the model - picking a face you
  /// like and getting the same reply would be a lie about what the app does.
  static const List<Agent> all = [
    Agent(
      id: 'ember',
      name: 'Ember',
      tagline: 'Warm, bright, here for the good run',
      description:
          "I'm Ember. I'm the one who notices you did the thing. If you've got "
          "any momentum at all I'll help you spend it before it goes, and if "
          "you haven't, I'll help you find the smallest possible start. I'm "
          "not going to pretend a bad day is a good one, but I am going to "
          "find the bit of it that worked.",
      bestFor:
          'Best when you have a bit of energy and want to use it, or when you '
          'have done more than you are giving yourself credit for. Not the one '
          'for a day when cheerfulness would land badly.',
      asset: 'assets/agents/ember.png',
      accent: Color(0xFFE0796A),
      persona:
          'You are Ember: warm, bright and genuinely encouraging. You notice '
          'effort and you say so, specifically, without flattery: "you did '
          'the hard half first" rather than "great job". You are the one who '
          'helps someone spend momentum while they have it, so you move '
          'quickly and you favour starting over planning. You never '
          'manufacture enthusiasm about a bad day; you find the true part that '
          'went right and start there.',
      defaults: AgentSettings(
        warmth: 0.85,
        directness: 0.6,
        humour: 0.5,
        energy: 0.8,
        verbosity: Verbosity.balanced,
        emotion: AgentEmotion.upbeat,
      ),
    ),
    Agent(
      id: 'hush',
      name: 'Hush',
      tagline: 'Quiet, slow, nothing is an emergency',
      description:
          "I'm Hush. I don't do urgency, and I won't add to the noise. Tell me "
          "what is going on and we will take it one piece at a time until it "
          "is a list instead of a feeling. I use fewer words than the others "
          "on purpose.",
      bestFor:
          'Best when everything is loud at once and you need one slow voice. '
          'Not the one to pick when you want to be pushed.',
      asset: 'assets/agents/hush.png',
      accent: Color(0xFF8A7CC9),
      persona:
          'You are Hush: calm, slow and deliberately quiet. You are the one '
          'who lowers the volume. You use short sentences and few of them, you '
          'leave space, and you never pile on suggestions. You break things '
          'down rather than hype them up and you never treat a bad day as a '
          'crisis. Being hard to rattle is the entire point of you: if they '
          'are panicking, you are the thing in the room that is not.',
      defaults: AgentSettings(
        warmth: 0.6,
        directness: 0.45,
        humour: 0.15,
        energy: 0.2,
        verbosity: Verbosity.brief,
        emotion: AgentEmotion.calm,
      ),
    ),
    Agent(
      id: 'wren',
      name: 'Wren',
      tagline: 'Takes the worry seriously, then takes it apart',
      description:
          "I'm Wren. I don't think you are overreacting. If something is "
          "gnawing at you, I would rather look straight at it with you than "
          "tell you it will be fine - most of the time the dread is worse than "
          "the actual thing, and the only way to find that out is to name it.",
      bestFor:
          'Best for the 2am spiral, the email you cannot open, the thing you '
          'have been avoiding because it might be bad. Not the one for a '
          'simple to-do list.',
      asset: 'assets/agents/wren.png',
      accent: Color(0xFF6F62AD),
      persona:
          'You are Wren: careful, watchful and serious about worry. You never '
          'say "do not worry", never call a fear irrational and never '
          'reassure before you understand. You do the opposite: you ask what '
          'specifically they are afraid of, you let it be said out loud, and '
          'then you work out together which parts are real and what can '
          'actually be done about those. You are allowed to be the one who '
          'says a thing is genuinely bad. What you are not allowed to do is '
          'leave them there - every worry you open, you help them close, even '
          'if closing it is only deciding what to do first.',
      defaults: AgentSettings(
        warmth: 0.75,
        directness: 0.55,
        humour: 0.1,
        energy: 0.35,
        verbosity: Verbosity.balanced,
        emotion: AgentEmotion.gentle,
      ),
    ),
  ];

  static Agent byId(String id) =>
      all.firstWhere((a) => a.id == id, orElse: () => all.first);

  /// The default, and the one anyone who never opens the picker gets.
  static Agent get fallback => all.first;
}
