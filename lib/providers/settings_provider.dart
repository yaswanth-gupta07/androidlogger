import 'package:flutter/material.dart';

import '../models/event_type.dart';
import '../services/preference_store.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this._preferences, {this.version = '1.0.0'});

  static const _themeKey = 'theme_mode';
  static const _categoriesKey = 'enabled_categories';
  static const _loggingKey = 'logging_enabled';

  final PreferenceStore _preferences;
  ThemeMode themeMode = ThemeMode.system;
  bool loggingEnabled = false;
  String version;
  final Set<EventType> _enabled = {...EventType.values};

  Set<EventType> get enabledCategories => Set.unmodifiable(_enabled);

  bool isEnabled(EventType type) => _enabled.contains(type);

  Future<void> load() async {
    final theme = await _preferences.getString(_themeKey);
    themeMode = switch (theme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    final logging = await _preferences.getBool(_loggingKey);
    loggingEnabled = logging ?? false;
    final categories = await _preferences.getString(_categoriesKey);
    if (categories != null && categories.isNotEmpty) {
      final parsed = categories
          .split(',')
          .map(EventType.parse)
          .whereType<EventType>()
          .toSet();
      if (parsed.isNotEmpty) {
        _enabled
          ..clear()
          ..addAll(parsed);
      }
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _preferences.setString(_themeKey, mode.name);
  }

  Future<void> setCategoryEnabled(EventType type, bool enabled) async {
    if (enabled) {
      _enabled.add(type);
    } else {
      _enabled.remove(type);
    }
    notifyListeners();
    await _preferences.setString(
      _categoriesKey,
      _enabled.map((item) => item.name).join(','),
    );
  }

  Future<void> setLoggingEnabled(bool enabled) async {
    loggingEnabled = enabled;
    notifyListeners();
    await _preferences.setBool(_loggingKey, enabled);
  }

  void setVersion(String value) {
    version = value;
    notifyListeners();
  }
}
