import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/device_status_provider.dart';
import 'providers/dropbox_provider.dart';
import 'providers/logging_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/dashboard_screen.dart';
import 'screens/dropbox_screen.dart';
import 'screens/logs_screen.dart';
import 'screens/privacy_screen.dart';
import 'screens/settings_screen.dart';
import 'services/dropbox_api.dart';
import 'theme/app_theme.dart';

class AppScope {
  AppScope({
    required this.settings,
    required this.deviceStatus,
    required this.logging,
    required this.dropbox,
    this.httpApi,
  });

  final SettingsController settings;
  final DeviceStatusController deviceStatus;
  final LoggingController logging;
  final DropboxController dropbox;
  final HttpDropboxApi? httpApi;
  bool _disposed = false;

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    logging.dispose();
    deviceStatus.dispose();
    dropbox.dispose();
    settings.dispose();
    httpApi?.close();
  }
}

class AndroidLoggerApp extends StatefulWidget {
  const AndroidLoggerApp({super.key, required this.scope});

  final AppScope scope;

  @override
  State<AndroidLoggerApp> createState() => _AndroidLoggerAppState();
}

class _AndroidLoggerAppState extends State<AndroidLoggerApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final scope = widget.scope;
      scope.logging.attachLifecycle();
      if (scope.settings.loggingEnabled && !scope.logging.isLogging) {
        scope.logging.startLogging();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsController>.value(value: scope.settings),
        ChangeNotifierProvider<DeviceStatusController>.value(
          value: scope.deviceStatus,
        ),
        ChangeNotifierProvider<LoggingController>.value(value: scope.logging),
        ChangeNotifierProvider<DropboxController>.value(value: scope.dropbox),
      ],
      child: const LoggerMaterialApp(),
    );
  }
}

class LoggerMaterialApp extends StatelessWidget {
  const LoggerMaterialApp({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    return MaterialApp(
      key: const ValueKey('android_logger_app'),
      debugShowCheckedModeBanner: false,
      title: 'Android Logger',
      themeMode: settings.themeMode,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      home: const DashboardScreen(),
      routes: {
        LogsScreen.route: (_) => const LogsScreen(),
        DropboxScreen.route: (_) => const DropboxScreen(),
        SettingsScreen.route: (_) => const SettingsScreen(),
        PrivacyScreen.route: (_) => const PrivacyScreen(),
      },
    );
  }
}
