import 'package:flutter/widgets.dart';

import 'om_icons.dart';

/// Picks an icon for a task from what it says.
///
/// Blocks arrive from typing, from a brain dump and from goal breakdowns, so
/// nothing can be tagged by hand. Matching on the title keeps a schedule
/// scannable: you find "gym" by its shape before you read the word.
///
/// Order matters. The first hit wins, so the specific patterns are listed
/// before the broad ones ("coffee" before "break").
IconData taskIcon(String title, {String fallback = 'checksq'}) {
  final t = title.toLowerCase();

  for (final entry in _rules) {
    for (final word in entry.value) {
      if (t.contains(word)) return OmIcons.byName(entry.key);
    }
  }
  return OmIcons.byName(fallback);
}

/// Keyword groups, most specific first.
const List<MapEntry<String, List<String>>> _rules = [
  // Routine anchors.
  MapEntry('sun', ['wake up', 'wake-up', 'morning routine', 'sunrise']),
  MapEntry('bed', ['sleep', 'wind down', 'wind-down', 'bedtime', 'nap']),

  // Health and body.
  MapEntry('pill', ['medication', 'meds', 'pill', 'vitamin', 'prescription']),
  MapEntry('activity', ['gym', 'workout', 'exercise', 'run', 'walk', 'stretch', 'yoga', 'training']),
  MapEntry('droplet', ['water', 'hydrate', 'drink']),
  MapEntry('wind', ['breathe', 'breathing', 'meditat', 'calm']),
  MapEntry('heart', ['therapy', 'doctor', 'dentist', 'appointment', 'clinic', 'checkup']),

  // Work and study.
  MapEntry('brain', ['deep work', 'focus', 'study', 'revise', 'research', 'think']),
  MapEntry('book', ['read', 'book', 'chapter', 'article', 'notes', 'lecture']),
  MapEntry('keyboard', ['code', 'coding', 'build', 'debug', 'program', 'ship', 'deploy', 'bug']),
  MapEntry('file-text', ['write', 'draft', 'report', 'essay', 'document', 'assignment', 'cv', 'resume']),
  MapEntry('users', ['meeting', 'standup', 'sync', 'interview', 'presentation', 'team']),
  MapEntry('message', ['call', 'email', 'reply', 'message', 'text', 'chat', 'follow up', 'follow-up']),

  // Life admin.
  MapEntry('list', ['groceries', 'shopping', 'buy', 'order', 'errand']),
  MapEntry('home', ['clean', 'tidy', 'laundry', 'dishes', 'chores', 'house']),
  MapEntry('coffee', ['coffee', 'lunch', 'dinner', 'breakfast', 'eat', 'meal', 'cook', 'break']),
  MapEntry('calendar', ['plan', 'schedule', 'book a', 'organise', 'organize']),
  MapEntry('target', ['goal', 'milestone', 'deadline', 'submit', 'finish']),
];
