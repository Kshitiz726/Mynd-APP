/// A thought the user parked mid-session rather than chasing it.
///
/// Parking is the ADHD move: the intrusive thought gets somewhere safe to sit
/// so it stops interrupting, and it later feeds the memory the coach reads.
class ParkedThought {
  const ParkedThought({required this.id, required this.text, required this.at});

  final String id;
  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'at': at.toIso8601String()};

  factory ParkedThought.fromJson(Map<String, dynamic> j) => ParkedThought(
        id: j['id'] as String,
        text: j['text'] as String,
        at: DateTime.tryParse(j['at'] as String? ?? '') ?? DateTime.now(),
      );
}

/// What the app knows about you, in your own words or the AI's.
///
/// This is deliberately a single block of prose rather than a structured
/// profile: it is meant to be *read* by the user and corrected by hand, and
/// nobody edits a JSON blob. [userEdited] records that the user has touched it,
/// which the next AI pass is told to respect rather than overwrite.
class UserMemory {
  const UserMemory({this.text = '', this.updatedAt, this.userEdited = false});

  final String text;
  final DateTime? updatedAt;
  final bool userEdited;

  bool get isEmpty => text.trim().isEmpty;

  UserMemory copyWith({String? text, DateTime? updatedAt, bool? userEdited}) => UserMemory(
        text: text ?? this.text,
        updatedAt: updatedAt ?? this.updatedAt,
        userEdited: userEdited ?? this.userEdited,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'updatedAt': updatedAt?.toIso8601String(),
        'userEdited': userEdited,
      };

  factory UserMemory.fromJson(Map<String, dynamic> j) => UserMemory(
        text: j['text'] as String? ?? '',
        updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
        userEdited: j['userEdited'] == true,
      );
}
