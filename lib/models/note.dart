class Note {
  Note({
    required this.id,
    required this.title,
    required this.preview,
    required this.content,
    required this.tags,
    required this.isPinned,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String preview;
  final String content;
  final List<String> tags;
  final bool isPinned;
  final DateTime updatedAt;

  factory Note.fromJson(Map<String, dynamic> json) {
    return Note(
      id: json['_id'] as String,
      title: json['title'] as String,
      preview: json['preview'] as String,
      content: json['content'] as String,
      tags: (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      isPinned: json['isPinned'] as bool? ?? false,
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }
}
