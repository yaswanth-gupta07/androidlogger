import 'package:shared_preferences/shared_preferences.dart';

abstract class PreferenceStore {
  Future<String?> getString(String key);
  Future<void> setString(String key, String value);
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
  Future<void> remove(String key);
}

class MemoryPreferenceStore implements PreferenceStore {
  final Map<String, Object?> values = {};

  @override
  Future<String?> getString(String key) async => values[key] as String?;

  @override
  Future<void> setString(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<bool?> getBool(String key) async => values[key] as bool?;

  @override
  Future<void> setBool(String key, bool value) async {
    values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }
}

class SharedPreferenceStore implements PreferenceStore {
  SharedPreferenceStore(this._preferences);

  final SharedPreferences _preferences;

  @override
  Future<String?> getString(String key) async => _preferences.getString(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<bool?> getBool(String key) async => _preferences.getBool(key);

  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);
}
