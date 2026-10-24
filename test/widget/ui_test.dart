import 'dart:async';
import 'dart:io';

import 'package:android_logger/app.dart';
import 'package:android_logger/models/device_snapshot.dart';
import 'package:android_logger/models/event_type.dart';
import 'package:android_logger/models/log_event.dart';
import 'package:android_logger/models/sync_status.dart';
import 'package:android_logger/platform/system_event_source.dart';
import 'package:android_logger/providers/device_status_provider.dart';
import 'package:android_logger/providers/dropbox_provider.dart';
import 'package:android_logger/providers/logging_provider.dart';
import 'package:android_logger/providers/settings_provider.dart';
import 'package:android_logger/services/battery_service.dart';
import 'package:android_logger/services/dropbox_api.dart';
import 'package:android_logger/services/dropbox_auth_service.dart';
import 'package:android_logger/services/dropbox_sync_service.dart';
import 'package:android_logger/services/event_logger_service.dart';
import 'package:android_logger/services/log_storage_service.dart';
import 'package:android_logger/services/network_service.dart';
import 'package:android_logger/services/preference_store.dart';
import 'package:android_logger/services/secure_store.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ScriptedBattery implements BatterySource {
  ScriptedBattery(this.current);

  BatterySnapshot current;
  final StreamController<BatterySnapshot> controller =
      StreamController<BatterySnapshot>.broadcast();

  @override
  Future<void> start() async {}

  @override
  Future<BatterySnapshot> readCurrent() async => current;

  @override
  Stream<BatterySnapshot> get changes => controller.stream;

  @override
  Future<void> dispose() async {
    await controller.close();
  }
}

class ScriptedConnectivity implements ConnectivitySource {
  ScriptedConnectivity(this.current);

  List<ConnectivityResult> current;

  @override
  Future<List<ConnectivityResult>> check() async => current;

  @override
  Stream<List<ConnectivityResult>> get onChange => const Stream.empty();
}

Future<AppScope> buildScope({
  BatterySnapshot? battery,
  NetworkSnapshot? network,
  bool deviceLoading = false,
  String? deviceError,
  bool loggingLoading = false,
  String? loggingError,
  List<LogEvent> seeded = const [],
  bool connected = false,
  SyncStatus syncStatus = const SyncStatus(),
  ScriptedBattery? liveBattery,
}) async {
  // Synchronous creation avoids a FakeAsync deadlock in widget tests.
  final directory = Directory.systemTemp.createTempSync('android_logger_ui');
  final storage = MemoryLogStorage(directory);
  for (final event in seeded) {
    await storage.append(event);
  }
  final settings = SettingsController(MemoryPreferenceStore());
  final batterySource = liveBattery ?? const EmptyBatterySource();
  final device = DeviceStatusController(
    battery: batterySource,
    network: NetworkService(
      source: ScriptedConnectivity(const [ConnectivityResult.wifi]),
      probe: FakeInternetProbe(),
    ),
    system: const EmptySystemEventSource(),
    clockInterval: null,
    loading: deviceLoading,
    initialError: deviceError,
    initialBattery: battery,
    initialNetwork: network,
  );
  final logging = LoggingController(
    logger: EventLoggerService(storage: storage),
    storage: storage,
    settings: settings,
    deviceStatus: device,
    loading: loggingLoading,
    initialError: loggingError,
  );
  if (seeded.isNotEmpty) {
    await logging.load();
  }
  final api = FakeDropboxApi();
  final auth = DropboxAuthService(
    store: MemorySecureStore(),
    api: api,
    browser: (_) async => null,
  );
  final dropbox = DropboxController(
    auth: auth,
    sync: DropboxSyncService(api: api, auth: auth),
    deviceStatus: device,
    preferences: MemoryPreferenceStore(),
    exportText: logging.exportText,
    connected: connected,
    appKey: connected ? 'abc123xyz9' : '',
    status: syncStatus,
  );
  return AppScope(
    settings: settings,
    deviceStatus: device,
    logging: logging,
    dropbox: dropbox,
  );
}

void main() {
  Finder listScroller(Key listKey) {
    return find
        .descendant(of: find.byKey(listKey), matching: find.byType(Scrollable))
        .first;
  }

  Future<void> reveal(WidgetTester tester, Finder finder, Key listKey) async {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: listScroller(listKey),
    );
  }

  Future<void> scrollListToTop(WidgetTester tester, Key listKey) async {
    tester.state<ScrollableState>(listScroller(listKey)).position.jumpTo(0);
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester, AppScope scope) async {
    await tester.pumpWidget(const SizedBox());
    scope.dispose();
  }

  testWidgets('dashboard shows live status and start/stop controls', (
    tester,
  ) async {
    final battery = ScriptedBattery(
      const BatterySnapshot(
        level: 82,
        charge: ChargeState.charging,
        plug: 'usb',
      ),
    );
    final scope = await buildScope(
      liveBattery: battery,
      network: NetworkSnapshot(
        transports: transportsFrom(const [ConnectivityResult.wifi]),
        internetReachable: true,
      ),
    );
    await scope.deviceStatus.start();
    await tester.pumpWidget(AndroidLoggerApp(scope: scope));
    await tester.pump();

    expect(find.text('Android Logger'), findsOneWidget);
    expect(find.text('Real-Time Device Activity Monitor'), findsOneWidget);
    expect(find.text('○ LOGGING STOPPED'), findsOneWidget);
    expect(find.text('82%'), findsOneWidget);
    expect(find.text('Wi-Fi connected'), findsOneWidget);
    expect(find.text('Internet available'), findsOneWidget);
    expect(find.text('Start Logging'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('startLogging')))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('stopLogging')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('startLogging')));
    await tester.pump();
    await tester.pump();

    expect(find.text('● LOGGING ACTIVE'), findsOneWidget);
    await reveal(
      tester,
      find.text('Battery level is 82%'),
      const Key('dashboardList'),
    );
    expect(find.text('Battery level is 82%'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('startLogging')))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('stopLogging')))
          .onPressed,
      isNotNull,
    );

    battery.controller.add(
      const BatterySnapshot(
        level: 81,
        charge: ChargeState.charging,
        plug: 'usb',
      ),
    );
    await tester.pump();
    await tester.pump();

    await scrollListToTop(tester, const Key('dashboardList'));
    expect(find.text('81%'), findsOneWidget);
    await reveal(
      tester,
      find.text('Battery level changed to 81%'),
      const Key('dashboardList'),
    );
    expect(find.text('Battery level changed to 81%'), findsOneWidget);

    await tester.tap(find.byKey(const Key('stopLogging')));
    await tester.pump();
    await tester.pump();
    await scrollListToTop(tester, const Key('dashboardList'));
    expect(find.text('○ LOGGING STOPPED'), findsOneWidget);

    await tester.tap(find.byKey(const Key('viewLogs')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Search logs'), findsOneWidget);

    await finish(tester, scope);
  });

  testWidgets('dashboard shows loading, error, empty, and offline states', (
    tester,
  ) async {
    final loading = await buildScope(deviceLoading: true);
    await tester.pumpWidget(AndroidLoggerApp(scope: loading));
    await tester.pump();
    expect(find.text('Loading device information...'), findsOneWidget);
    await finish(tester, loading);

    final failed = await buildScope(
      deviceError: 'Unable to read device status.',
    );
    await tester.pumpWidget(AndroidLoggerApp(scope: failed));
    await tester.pump();
    expect(find.text('Unable to read device status.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await finish(tester, failed);

    final offline = await buildScope(
      battery: const BatterySnapshot(
        level: 50,
        charge: ChargeState.discharging,
        plug: 'none',
      ),
      network: const NetworkSnapshot.unavailable(),
    );
    await tester.pumpWidget(AndroidLoggerApp(scope: offline));
    await tester.pump();
    expect(find.textContaining("You're offline"), findsOneWidget);
    await reveal(
      tester,
      find.textContaining('No events recorded yet.'),
      const Key('dashboardList'),
    );
    expect(find.textContaining('No events recorded yet.'), findsOneWidget);
    await finish(tester, offline);
  });

  testWidgets('logs screen searches and filters stored events', (tester) async {
    final scope = await buildScope(
      seeded: [
        LogEvent(
          id: '1',
          timestamp: DateTime(2026, 10, 24, 13, 20, 30),
          type: EventType.battery,
          description: 'Battery level changed to 82%',
        ),
        LogEvent(
          id: '2',
          timestamp: DateTime(2026, 10, 24, 13, 21, 10),
          type: EventType.network,
          description: 'Wi-Fi connected',
        ),
      ],
    );
    await tester.pumpWidget(AndroidLoggerApp(scope: scope));
    await tester.pump();
    await tester.tap(find.byKey(const Key('viewLogs')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Battery level changed to 82%'), findsOneWidget);
    expect(find.text('Wi-Fi connected'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('logSearch')), 'wifi');
    await tester.pump();
    expect(find.text('Wi-Fi connected'), findsOneWidget);
    expect(find.text('Battery level changed to 82%'), findsNothing);

    await tester.enterText(find.byKey(const Key('logSearch')), '');
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter_network')));
    await tester.pump();
    expect(find.text('Battery level changed to 82%'), findsOneWidget);
    expect(find.text('Wi-Fi connected'), findsNothing);

    await finish(tester, scope);
  });

  testWidgets('logs screen shows an error state', (tester) async {
    final scope = await buildScope(loggingError: 'Unable to load logs.');
    await tester.pumpWidget(AndroidLoggerApp(scope: scope));
    await tester.pump();
    await tester.tap(find.byKey(const Key('viewLogs')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const Key('logsError')), findsOneWidget);
    expect(find.text('Unable to load logs.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await finish(tester, scope);
  });

  testWidgets('dropbox screen shows connection and sync states', (
    tester,
  ) async {
    final disconnected = await buildScope();
    await tester.pumpWidget(AndroidLoggerApp(scope: disconnected));
    await tester.pump();
    await tester.tap(find.byKey(const Key('syncDropbox')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Not Connected'), findsOneWidget);
    expect(find.text('Connect Dropbox'), findsOneWidget);
    await finish(tester, disconnected);

    final connected = await buildScope(
      connected: true,
      syncStatus: SyncStatus(
        lastSuccess: DateTime(2026, 10, 24, 13, 42),
        fileBytes: 24 * 1024,
      ),
    );
    await tester.pumpWidget(AndroidLoggerApp(scope: connected));
    await tester.pump();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('openDropboxSettings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Connected'), findsWidgets);
    expect(find.text('android_log.txt'), findsWidgets);
    expect(find.text('Sync Now'), findsOneWidget);
    await reveal(tester, find.text('Disconnect'), const Key('dropboxList'));
    expect(find.text('Disconnect'), findsOneWidget);
    await finish(tester, connected);

    final uploading = await buildScope(
      connected: true,
      syncStatus: const SyncStatus(
        phase: SyncPhase.uploading,
        progress: 0.8,
        message: 'Uploading...',
      ),
    );
    await tester.pumpWidget(AndroidLoggerApp(scope: uploading));
    await tester.pump();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('openDropboxSettings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Uploading...'), findsOneWidget);
    expect(find.text('80%'), findsOneWidget);
    await finish(tester, uploading);

    final success = await buildScope(
      connected: true,
      syncStatus: const SyncStatus(
        phase: SyncPhase.success,
        progress: 1,
        message: 'android_log.txt uploaded successfully.',
        fileBytes: 128,
      ),
    );
    await tester.pumpWidget(AndroidLoggerApp(scope: success));
    await tester.pump();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('openDropboxSettings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Sync Complete'), findsOneWidget);
    expect(find.textContaining('uploaded successfully'), findsOneWidget);
    await finish(tester, success);

    final failure = await buildScope(
      connected: true,
      syncStatus: const SyncStatus(
        phase: SyncPhase.failure,
        message: 'Unable to upload the log file.',
      ),
    );
    await tester.pumpWidget(AndroidLoggerApp(scope: failure));
    await tester.pump();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byKey(const Key('openDropboxSettings')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('Sync Failed'), findsOneWidget);
    expect(find.text('Unable to upload the log file.'), findsOneWidget);
    await reveal(
      tester,
      find.byKey(const Key('syncRetry')),
      const Key('dropboxList'),
    );
    expect(find.byKey(const Key('syncRetry')), findsOneWidget);
    await finish(tester, failure);
  });
}
