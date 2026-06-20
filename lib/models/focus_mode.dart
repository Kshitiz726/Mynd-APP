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

  static const List<FocusMode> presets = [
    FocusMode(name: 'Sprint', minutes: 15, iconName: 'zap', when: "when energy's low"),
    FocusMode(name: 'Pomodoro', minutes: 25, iconName: 'timer', when: 'the classic'),
    FocusMode(name: 'Deep Work', minutes: 45, iconName: 'brain', when: 'feeling it'),
    FocusMode(name: 'Flow', minutes: 90, iconName: 'waves', when: 'full hyperfocus'),
  ];
}
