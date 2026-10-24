/// Categories of device activity this application is allowed to record.
enum EventType {
  battery,
  network,
  charging,
  app,
  screen,
  audio,
  time;

  String get label => switch (this) {
    EventType.battery => 'BATTERY',
    EventType.network => 'NETWORK',
    EventType.charging => 'CHARGING',
    EventType.app => 'APP',
    EventType.screen => 'SCREEN',
    EventType.audio => 'AUDIO',
    EventType.time => 'TIME',
  };

  String get title => switch (this) {
    EventType.battery => 'Battery',
    EventType.network => 'Network',
    EventType.charging => 'Charging',
    EventType.app => 'App',
    EventType.screen => 'Screen',
    EventType.audio => 'Audio',
    EventType.time => 'Time',
  };

  static EventType? parse(Object? raw) {
    if (raw is! String) {
      return null;
    }
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) {
      return null;
    }
    for (final type in EventType.values) {
      if (type.name == value || type.label.toLowerCase() == value) {
        return type;
      }
    }
    return null;
  }
}
