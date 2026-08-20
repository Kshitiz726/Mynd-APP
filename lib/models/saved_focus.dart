/// A focus the user named and kept ("Read Atomic Habits", 30m).
///
/// Presets answer "how do I feel"; a saved focus answers "what am I working on"
/// - it survives restarts so the thing you keep coming back to is one tap away
/// instead of a dial spin plus a re-typed name.
class SavedFocus {
  const SavedFocus({
    required this.id,
    required this.name,
    required this.minutes,
    this.iconName = 'target',
  });

  final String id;
  final String name;
  final int minutes;
  final String iconName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'minutes': minutes,
        'iconName': iconName,
      };

  factory SavedFocus.fromJson(Map<String, dynamic> j) => SavedFocus(
        id: j['id'] as String,
        name: j['name'] as String,
        minutes: (j['minutes'] as num).toInt(),
        iconName: j['iconName'] as String? ?? 'target',
      );
}
