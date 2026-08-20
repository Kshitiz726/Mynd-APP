/// Visual presence state shown in the participant grid. Mirrors the server's
/// `participant_state` enum.
enum ParticipantState { active, inactive, muted, needHelp }

/// Mic indicator - the real audio track lives in LiveKit; this is just the
/// badge the grid renders.
enum MicState { muted, speaking, ptt }

ParticipantState _stateFrom(String s) => switch (s) {
      'inactive' => ParticipantState.inactive,
      'muted' => ParticipantState.muted,
      'need_help' => ParticipantState.needHelp,
      _ => ParticipantState.active,
    };

MicState _micFrom(String s) => switch (s) {
      'speaking' => MicState.speaking,
      'ptt' => MicState.ptt,
      _ => MicState.muted,
    };

/// One participant's live state inside a focus room.
class RoomParticipant {
  RoomParticipant({
    required this.userId,
    required this.displayName,
    required this.initial,
    required this.avatarColor,
    required this.state,
    required this.micState,
    this.task,
    this.mode,
    this.secondsRemaining,
    this.timerRunning = false,
  });

  final String userId;
  final String displayName;
  final String initial;
  final String avatarColor;
  ParticipantState state;
  MicState micState;

  // Session sync ("Finish quarterly report", 25m, ticking).
  String? task;
  String? mode;
  int? secondsRemaining;
  bool timerRunning;

  factory RoomParticipant.fromJson(Map<String, dynamic> j) {
    final session = j['session'] as Map<String, dynamic>?;
    return RoomParticipant(
      userId: j['userId'] as String,
      displayName: j['displayName'] as String? ?? 'Someone',
      initial: j['initial'] as String? ?? '?',
      avatarColor: j['avatarColor'] as String? ?? '#6366F1',
      state: _stateFrom(j['state'] as String? ?? 'active'),
      micState: _micFrom(j['micState'] as String? ?? 'muted'),
      task: session?['task'] as String?,
      mode: session?['mode'] as String?,
      secondsRemaining: session?['secondsRemaining'] as int?,
      timerRunning: session?['running'] as bool? ?? false,
    );
  }

  /// Apply a partial `participant_update` patch in place.
  void applyPatch(Map<String, dynamic> patch) {
    if (patch['state'] != null) state = _stateFrom(patch['state']);
    if (patch['micState'] != null) micState = _micFrom(patch['micState']);
    final s = patch['session'] as Map<String, dynamic>?;
    if (s != null) {
      task = s['task'] as String? ?? task;
      mode = s['mode'] as String? ?? mode;
      secondsRemaining = s['secondsRemaining'] as int? ?? secondsRemaining;
      timerRunning = s['running'] as bool? ?? timerRunning;
    }
  }
}
