import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'config/dropbox_config.dart';
import 'platform/system_event_source.dart';
import 'providers/device_status_provider.dart';
import 'providers/dropbox_provider.dart';
import 'providers/logging_provider.dart';
import 'providers/settings_provider.dart';
import 'services/battery_service.dart';
import 'services/dropbox_api.dart';
import 'services/dropbox_auth_service.dart';
import 'services/dropbox_sync_service.dart';
import 'services/event_logger_service.dart';
import 'services/log_storage_service.dart';
import 'services/network_service.dart';
import 'services/preference_store.dart';
import 'services/secure_store.dart';

/// Wires the production Android services. Widget tests build their own scope.
Future<AppScope> buildAppScope() async {
  final supportDirectory = await getApplicationSupportDirectory();
  final storage = LogStorageService(supportDirectory);
  final preferences = SharedPreferenceStore(
    await SharedPreferences.getInstance(),
  );
  final settings = SettingsController(preferences);
  await settings.load();

  final android = !kIsWeb && Platform.isAndroid;
  final system = android
      ? AndroidSystemEventSource()
      : const EmptySystemEventSource();
  final battery = android
      ? BatteryPlusSource(battery: Battery())
      : const EmptyBatterySource();
  final network = NetworkService(
    source: android
        ? PluginConnectivitySource(connectivity: Connectivity())
        : const EmptyConnectivitySource(),
    probe: android ? HttpInternetProbe() : FakeInternetProbe(online: false),
  );
  final deviceStatus = DeviceStatusController(
    battery: battery,
    network: network,
    system: system,
  );
  final logger = EventLoggerService(storage: storage);
  final logging = LoggingController(
    logger: logger,
    storage: storage,
    settings: settings,
    deviceStatus: deviceStatus,
  );
  await logging.load();

  final api = HttpDropboxApi();
  final auth = DropboxAuthService(
    store: FlutterSecureStore(const FlutterSecureStorage()),
    api: api,
    browser: (uri) async {
      try {
        return await FlutterWebAuth2.authenticate(
          url: uri.toString(),
          callbackUrlScheme: DropboxConfig.redirectScheme,
        );
      } on PlatformException catch (error) {
        if (error.code.toUpperCase().contains('CANCEL')) {
          return null;
        }
        throw DropboxException('Dropbox sign-in failed.');
      }
    },
  );
  final dropbox = DropboxController(
    auth: auth,
    sync: DropboxSyncService(api: api, auth: auth),
    deviceStatus: deviceStatus,
    preferences: preferences,
    exportText: logging.exportText,
  );
  await dropbox.load();
  await deviceStatus.start();
  try {
    final info = await PackageInfo.fromPlatform();
    settings.setVersion('${info.version}+${info.buildNumber}');
  } catch (_) {
    settings.setVersion('1.0.0');
  }
  return AppScope(
    settings: settings,
    deviceStatus: deviceStatus,
    logging: logging,
    dropbox: dropbox,
    httpApi: api,
  );
}
