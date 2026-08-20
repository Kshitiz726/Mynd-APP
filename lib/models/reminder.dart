/// How often a reminder comes back.
enum ReminderRepeat {
  once('Once'),
  daily('Daily');

  const ReminderRepeat(this.label);
  final String label;

  static ReminderRepeat fromName(String? n) =>
      ReminderRepeat.values.firstWhere((r) => r.name == n,
          orElse: () => ReminderRepeat.once);
}

/// One thing the user asked to be reminded about.
///
/// The time is stored as hour and minute rather than a [DateTime] because a
/// reminder is a time of day, not a moment: "9:00" survives midnight, a
/// timestamp does not.
class Reminder {
  Reminder({
    required this.id,
    required this.title,
    required this.hour,
    required this.minute,
    this.note = '',
    this.repeat = ReminderRepeat.once,
    this.enabled = true,
  });

  final String id;
  final String title;
  final String note;
  final int hour;
  final int minute;
  final ReminderRepeat repeat;
  final bool enabled;

  /// The notification id the OS knows this by. Derived from the string id so it
  /// is stable across launches: an unstable id means cancelling a reminder
  /// cancels nothing and the old one keeps firing.
  int get notificationId => id.hashCode & 0x7fffffff;

  /// The next time this should fire, in local time.
  DateTime nextOccurrence([DateTime? from]) {
    final now = from ?? DateTime.now();
    var at = DateTime(now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    return at;
  }

  Reminder copyWith({
    String? title,
    String? note,
    int? hour,
    int? minute,
    ReminderRepeat? repeat,
    bool? enabled,
  }) =>
      Reminder(
        id: id,
        title: title ?? this.title,
        note: note ?? this.note,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        repeat: repeat ?? this.repeat,
        enabled: enabled ?? this.enabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'h': hour,
        'm': minute,
        'repeat': repeat.name,
        'on': enabled,
      };

  static Reminder fromJson(Map<String, dynamic> j) => Reminder(
        id: (j['id'] ?? '') as String,
        title: (j['title'] ?? '') as String,
        note: (j['note'] ?? '') as String,
        hour: (j['h'] ?? 9) as int,
        minute: (j['m'] ?? 0) as int,
        repeat: ReminderRepeat.fromName(j['repeat'] as String?),
        enabled: (j['on'] ?? true) as bool,
      );
}
