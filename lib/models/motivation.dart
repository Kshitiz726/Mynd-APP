/// The areas somebody wants to work on, and how the day's lines are weighted.
///
/// Taken from the reference design's third screen. They are not moods: a mood
/// is how you are right now and it changes hourly, while these are what you
/// want said to you, and they hold for months. Both feed the same line - the
/// category decides the subject, the mood decides the tone - which is why a
/// "rough" day under Achieving goals gets encouragement rather than a push.
enum MotivationCategory {
  lettingGo(label: 'Letting go'),
  faith(label: 'Faith & Spirituality'),
  happiness(label: 'Happiness'),
  stress(label: 'Stress & Anxiety'),
  health(label: 'Health & Fitness'),
  goals(label: 'Achieving goals'),
  selfEsteem(label: 'Self-esteem'),
  relationships(label: 'Relationships');

  const MotivationCategory({required this.label});

  final String label;

  static MotivationCategory? byName(String n) {
    for (final v in values) {
      if (v.name == n) return v;
    }
    return null;
  }
}

/// How often, and between which hours, the day's motivation arrives.
///
/// Minutes since midnight rather than TimeOfDay, because this is persisted and
/// a stored clock reading has to survive a locale change without meaning a
/// different time.
class MotivationSettings {
  const MotivationSettings({
    this.count = 10,
    this.startMinutes = 9 * 60,
    this.endMinutes = 22 * 60,
    this.categories = const {},
    this.onboarded = false,
  });

  /// How many lines a day. Capped where it is scheduled, not here, because the
  /// limit is the OS pending-notification budget rather than anything about
  /// what a person can stand.
  final int count;

  final int startMinutes;
  final int endMinutes;
  final Set<MotivationCategory> categories;

  /// Whether the setup flow has been completed. Distinct from "has categories":
  /// somebody can finish setup having picked none, and should not be asked
  /// again for it.
  final bool onboarded;

  /// The window the lines are spread across. Negative when the end is before
  /// the start, which the picker prevents but stored data from an older build
  /// might still hold.
  int get spanMinutes => endMinutes - startMinutes;

  bool get valid => spanMinutes > 0 && count > 0;

  /// The clock times to fire at, evenly spread across the window.
  ///
  /// The first lands on the start and the last on the end, so "9am to 10pm"
  /// means what it says rather than the first arriving an interval late. A
  /// single line a day lands at the start, since an average of two times
  /// somebody chose is a time neither of them meant.
  List<int> get slotMinutes {
    if (!valid) return const [];
    if (count == 1) return [startMinutes];
    final step = spanMinutes / (count - 1);
    return [
      for (var i = 0; i < count; i++) (startMinutes + step * i).round(),
    ];
  }

  MotivationSettings copyWith({
    int? count,
    int? startMinutes,
    int? endMinutes,
    Set<MotivationCategory>? categories,
    bool? onboarded,
  }) =>
      MotivationSettings(
        count: count ?? this.count,
        startMinutes: startMinutes ?? this.startMinutes,
        endMinutes: endMinutes ?? this.endMinutes,
        categories: categories ?? this.categories,
        onboarded: onboarded ?? this.onboarded,
      );

  Map<String, dynamic> toJson() => {
        'count': count,
        'start': startMinutes,
        'end': endMinutes,
        'categories': categories.map((c) => c.name).toList(),
        'onboarded': onboarded,
      };

  factory MotivationSettings.fromJson(Map<String, dynamic> j) =>
      MotivationSettings(
        count: j['count'] is int ? j['count'] as int : 10,
        startMinutes: j['start'] is int ? j['start'] as int : 9 * 60,
        endMinutes: j['end'] is int ? j['end'] as int : 22 * 60,
        categories: {
          for (final n in (j['categories'] as List? ?? const []))
            if (n is String && MotivationCategory.byName(n) != null)
              MotivationCategory.byName(n)!,
        },
        onboarded: j['onboarded'] == true,
      );
}

/// One line, and where it came from.
///
/// [source] is kept so the app can say "because of what is happening in
/// Bristol today" rather than presenting a generated sentence as if it fell
/// out of the sky. A line whose reason cannot be shown is a line nobody can
/// argue with.
class MotivationLine {
  const MotivationLine({
    required this.text,
    required this.at,
    this.category,
    this.place,
    this.source,
  });

  final String text;
  final DateTime at;
  final MotivationCategory? category;

  /// The town or city the news came from, when there was one.
  final String? place;

  /// The headline this was written against, if any.
  final String? source;

  Map<String, dynamic> toJson() => {
        'text': text,
        'at': at.toIso8601String(),
        if (category != null) 'category': category!.name,
        if (place != null) 'place': place,
        if (source != null) 'source': source,
      };

  factory MotivationLine.fromJson(Map<String, dynamic> j) => MotivationLine(
        text: j['text'] as String? ?? '',
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
        category: MotivationCategory.byName(j['category'] as String? ?? ''),
        place: j['place'] as String?,
        source: j['source'] as String?,
      );
}
