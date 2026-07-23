/// A focus-session preset. The four presets map directly to the prototype's
/// mode selector and are intentionally framed by *how you feel*, not just by
/// duration.
class FocusMode {
  const FocusMode({
    required this.name,
    required this.minutes,
    required this.iconName,
    required this.when,
  });

  final String name;
  final int minutes;
  final String iconName;

  /// The ADHD-friendly "use it when…" hint.
  final String when;

  /// The value the server's `focus_mode_kind` enum accepts
  /// (`sprint|pomodoro|deep_work|flow|custom`). A preset maps to its own kind;
  /// anything else - a session named after a task, or a saved focus - is
  /// 'custom'. Sending a raw [name] here is what crashed the sessions insert.
  String get serverMode {
    switch (name.toLowerCase().trim()) {
      case 'sprint':
        return 'sprint';
      case 'pomodoro':
        return 'pomodoro';
      case 'deep work':
      case 'deep_work':
        return 'deep_work';
      case 'flow':
        return 'flow';
      default:
        return 'custom';
    }
  }

  static const List<FocusMode> presets = [
    FocusMode(name: 'Sprint', minutes: 15, iconName: 'zap', when: "when energy's low"),
    FocusMode(name: 'Pomodoro', minutes: 25, iconName: 'timer', when: 'the classic'),
    FocusMode(name: 'Deep Work', minutes: 45, iconName: 'brain', when: 'feeling it'),
    FocusMode(name: 'Flow', minutes: 90, iconName: 'waves', when: 'full hyperfocus'),
  ];
}
