import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/alarm.dart';

class AlarmsProvider extends ChangeNotifier {
  AlarmsProvider() {
    _load();
  }

  List<Alarm> _alarms = [];
  List<Alarm> get alarms => List.unmodifiable(_alarms);

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('om_alarms');
    if (raw != null) {
      final list = jsonDecode(raw) as List;
      _alarms = list.map((e) => Alarm.fromJson(e as Map<String, dynamic>)).toList();
    } else {
      _alarms = [
        Alarm(id: '1', time: '6:30', label: 'wake up', repeat: 'Mon-Fri', ringtone: 'Default'),
        Alarm(id: '2', time: '7:15', label: 'meds + water', repeat: 'every day', ringtone: 'Chime'),
      ];
      _save();
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    final raw = jsonEncode(_alarms.map((a) => a.toJson()).toList());
    await p.setString('om_alarms', raw);
  }

  void addAlarm(Alarm a) {
    _alarms.add(a);
    _save();
    notifyListeners();
  }

  void removeAlarm(String id) {
    _alarms.removeWhere((a) => a.id == id);
    _save();
    notifyListeners();
  }

  void updateAlarm(Alarm a) {
    final idx = _alarms.indexWhere((x) => x.id == a.id);
    if (idx != -1) {
      _alarms[idx] = a;
      _save();
      notifyListeners();
    }
  }

  void toggleEnabled(String id, bool enabled) {
    final idx = _alarms.indexWhere((x) => x.id == id);
    if (idx != -1) {
      _alarms[idx].enabled = enabled;
      _save();
      notifyListeners();
    }
  }
}
