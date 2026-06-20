import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/services/api_client.dart';
import '../models/note.dart';

class NotesProvider extends ChangeNotifier {
  NotesProvider(this._api);

  final ApiClient _api;

  List<Note> _notes = [];
  List<Note> get allNotes => _notes;
  List<Note> get pinnedNotes => _notes.where((n) => n.isPinned).toList();
  List<Note> get recentNotes => _notes.where((n) => !n.isPinned).toList();

  bool _loading = false;
  bool get loading => _loading;

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  Timer? _debounce;

  Future<void> fetchNotes() async {
    _loading = true;
    notifyListeners();
    try {
      final path = _searchQuery.isNotEmpty ? '/api/notes?q=${Uri.encodeComponent(_searchQuery)}' : '/api/notes';
      final res = await _api.get(path);
      if (res != null) {
        final list = res as List<dynamic>;
        _notes = list.map((e) => Note.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {
      // Handle error quietly
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void search(String query) {
    _searchQuery = query;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      fetchNotes();
    });
  }

  Future<Note?> createNote(String title, String content, List<String> tags) async {
    try {
      final res = await _api.post('/api/notes', {
        'title': title,
        'preview': content.length > 50 ? '${content.substring(0, 50)}...' : content,
        'content': content,
        'tags': tags,
      });
      if (res != null) {
        final note = Note.fromJson(res as Map<String, dynamic>);
        _notes.insert(0, note);
        notifyListeners();
        return note;
      }
    } catch (_) {}
    return null;
  }

  Future<void> togglePin(Note note) async {
    try {
      final updated = !note.isPinned;
      final res = await _api.put('/api/notes/${note.id}', {'isPinned': updated});
      if (res != null) {
        final newNote = Note.fromJson(res as Map<String, dynamic>);
        final idx = _notes.indexWhere((n) => n.id == note.id);
        if (idx != -1) {
          _notes[idx] = newNote;
          notifyListeners();
        }
      }
    } catch (_) {}
  }

  Future<Note?> updateNote(String id, String title, String content, List<String> tags) async {
    try {
      final res = await _api.put('/api/notes/$id', {
        'title': title,
        'preview': content.length > 50 ? '${content.substring(0, 50)}...' : content,
        'content': content,
        'tags': tags,
      });
      if (res != null) {
        final newNote = Note.fromJson(res as Map<String, dynamic>);
        final idx = _notes.indexWhere((n) => n.id == id);
        if (idx != -1) {
          _notes[idx] = newNote;
          notifyListeners();
          return newNote;
        }
      }
    } catch (_) {}
    return null;
  }
}
