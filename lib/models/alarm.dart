class Alarm {
  Alarm({
    required this.id,
    required this.time,
    required this.label,
    required this.repeat,
    required this.ringtone,
    this.enabled = true,
  });

  final String id;
  String time; // Format like '6:30'
  String label;
  String repeat;
  String ringtone;
  bool enabled;
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'time': time,
    'label': label,
    'repeat': repeat,
    'ringtone': ringtone,
    'enabled': enabled,
  };

  factory Alarm.fromJson(Map<String, dynamic> j) => Alarm(
    id: j['id'] as String,
    time: j['time'] as String,
    label: j['label'] as String,
    repeat: j['repeat'] as String,
    ringtone: j['ringtone'] as String,
    enabled: j['enabled'] as bool? ?? true,
  );
}
