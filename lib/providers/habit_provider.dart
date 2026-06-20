import 'package:flutter/material.dart';

import '../models/habit.dart';

/// Owns the habit boards shown as a snap-scrolling carousel on Home.
class HabitProvider extends ChangeNotifier {
  HabitProvider() : _boards = _seed();

  final List<HabitBoard> _boards;
  int _activeBoard = 0;

  List<HabitBoard> get boards => List.unmodifiable(_boards);
  int get activeBoard => _activeBoard;

  void setActiveBoard(int index) {
    if (index == _activeBoard || index < 0 || index >= _boards.length) return;
    _activeBoard = index;
    notifyListeners();
  }

  void toggle(Habit habit) {
    habit.done = !habit.done;
    notifyListeners();
  }

  static List<HabitBoard> _seed() => [
        HabitBoard(id: 'morning', name: 'Morning', items: [
          Habit(id: 'h-hydrate', iconName: 'droplet', name: 'hydrate', color: const Color(0xFF22D3EE)),
          Habit(id: 'h-stretch', iconName: 'activity', name: 'stretch', color: const Color(0xFF4ADE80)),
          Habit(id: 'h-meds', iconName: 'pill', name: 'meds', color: const Color(0xFFF472B6), done: true),
          Habit(id: 'h-sun', iconName: 'sun', name: 'sunlight', color: const Color(0xFFFACC15)),
        ]),
        HabitBoard(id: 'focus', name: 'Focus', items: [
          Habit(
            id: 'h-deep',
            iconName: 'brain',
            name: 'deep work',
            color: const Color(0xFFC084FC),
            kind: HabitKind.timer,
            minutes: 45,
          ),
          Habit(
            id: 'h-breathe',
            iconName: 'wind',
            name: 'breathe',
            color: const Color(0xFF60A5FA),
            kind: HabitKind.timer,
            minutes: 5,
          ),
          Habit(id: 'h-coffee', iconName: 'coffee', name: 'coffee', color: const Color(0xFFFB923C)),
        ]),
        HabitBoard(id: 'evening', name: 'Evening', items: [
          Habit(id: 'h-journal', iconName: 'message', name: 'journal', color: const Color(0xFF2DD4BF)),
          Habit(id: 'h-sleep', iconName: 'bed', name: 'sleep', color: const Color(0xFF818CF8)),
        ]),
      ];
}
