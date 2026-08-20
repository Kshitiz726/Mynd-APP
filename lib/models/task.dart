import 'energy_level.dart';

/// A single ADHD-friendly micro-step within a task. Breaking work into tiny,
/// unambiguous actions ("open last quarter's deck", "write just the 3 headers")
/// is a core anti-overwhelm mechanic.
class MicroStep {
  MicroStep({required this.text, this.done = false});

  final String text;
  bool done;

  Map<String, dynamic> toJson() => {'text': text, 'done': done};

  factory MicroStep.fromJson(Map<String, dynamic> j) =>
      MicroStep(text: j['text'] as String? ?? '', done: j['done'] as bool? ?? false);
}

/// A task in the backlog / timeline.
class Task {
  Task({
    required this.id,
    required this.title,
    required this.time,
    required this.energy,
    this.done = false,
    this.expanded = false,
    this.scheduled = false,
    this.startTime,
    this.duration,
    this.isAnchor = false,
    this.goalId,
    this.goalTitle,
    this.chunkOf,
    this.chunkIndex = 0,
    this.chunkCount = 0,
    List<MicroStep>? steps,
  }) : steps = steps ?? [];

  final String id;
  final String title;

  /// When Auto-Schedule splits a heavy task into focus blocks, each block is a
  /// chunk: [chunkOf] is the parent task id, and [chunkIndex]/[chunkCount] give
  /// the "part X of Y" position used for the block label.
  final String? chunkOf;
  final int chunkIndex;
  final int chunkCount;

  bool get isChunk => chunkOf != null;

  /// True for the fixed Wake/Sleep routine blocks. Anchors are ambient - they
  /// stay on the timeline all day and never fall into the backlog just because
  /// their clock time has passed.
  bool isAnchor;

  /// When this task was generated from a goal breakdown, the owning goal's id
  /// and title (used to render the block distinctly + roll progress back up).
  final String? goalId;
  final String? goalTitle;

  bool get isGoalTask => goalId != null;

  /// Human-readable time hint from the prototype ("now", "3:00 PM", "anytime").
  final String time;

  final EnergyLevel energy;
  bool done;

  /// Whether the micro-steps drawer is open in the UI.
  bool expanded;

  /// Whether the task has been placed on the day timeline.
  bool scheduled;

  /// The scheduled start time.
  DateTime? startTime;

  /// The allocated duration.
  Duration? duration;

  final List<MicroStep> steps;

  bool get hasSteps => steps.isNotEmpty;
  int get stepCount => steps.length;

  /// The scheduled end time.
  DateTime? get endTime => startTime?.add(duration ?? const Duration(hours: 1));

  /// True if the scheduled time has passed and the task is not done.
  /// Anchors (Wake/Sleep) are never "missed" - they stay pinned to the day and
  /// must not leak into the backlog when the clock rolls past them.
  bool get isMissed {
    if (done || isAnchor || endTime == null) return false;
    return endTime!.isBefore(DateTime.now());
  }

  // ── Persistence ──
  //
  // A day that vanishes on relaunch reads as data loss, so the whole task list
  // is written to disk. Everything the timeline needs to redraw a block is here;
  // [expanded] is deliberately not, because a drawer left open is a UI mood
  // rather than something worth restoring.

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'time': time,
        'energy': energy.name,
        'done': done,
        'scheduled': scheduled,
        if (startTime != null) 'startTime': startTime!.toIso8601String(),
        if (duration != null) 'durationMin': duration!.inMinutes,
        'isAnchor': isAnchor,
        if (goalId != null) 'goalId': goalId,
        if (goalTitle != null) 'goalTitle': goalTitle,
        if (chunkOf != null) 'chunkOf': chunkOf,
        'chunkIndex': chunkIndex,
        'chunkCount': chunkCount,
        if (steps.isNotEmpty) 'steps': steps.map((s) => s.toJson()).toList(),
      };

  factory Task.fromJson(Map<String, dynamic> j) {
    final mins = j['durationMin'] as int?;
    return Task(
      id: j['id'] as String,
      title: j['title'] as String? ?? '',
      time: j['time'] as String? ?? 'today',
      energy: EnergyLevel.values.firstWhere(
        (e) => e.name == j['energy'],
        orElse: () => EnergyLevel.low,
      ),
      done: j['done'] as bool? ?? false,
      scheduled: j['scheduled'] as bool? ?? false,
      startTime: j['startTime'] == null ? null : DateTime.parse(j['startTime'] as String),
      duration: mins == null ? null : Duration(minutes: mins),
      isAnchor: j['isAnchor'] as bool? ?? false,
      goalId: j['goalId'] as String?,
      goalTitle: j['goalTitle'] as String?,
      chunkOf: j['chunkOf'] as String?,
      chunkIndex: j['chunkIndex'] as int? ?? 0,
      chunkCount: j['chunkCount'] as int? ?? 0,
      steps: (j['steps'] as List?)
          ?.map((s) => MicroStep.fromJson((s as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}
