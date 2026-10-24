import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/event_type.dart';
import '../models/log_event.dart';
import '../services/app_lifecycle_service.dart';
import '../services/charging_service.dart';
import '../services/event_logger_service.dart';
import '../services/log_storage_service.dart';
import '../services/network_service.dart';
import 'device_status_provider.dart';
import 'settings_provider.dart';

class LoggingController extends ChangeNotifier {
  LoggingController({
    required EventLoggerService logger,
    required LogStore storage,
    required SettingsController settings,
    required DeviceStatusController deviceStatus,
    DateTime Function()? now,
    bool loading = false,
    String? initialError,
    List<LogEvent>? initialEvents,
  }) : _logger = logger,
       _storage = storage,
       _settings = settings,
       _device = deviceStatus,
       _now = now ?? DateTime.now,
       _loading = loading,
       _loadError = initialError,
       events = List<LogEvent>.of(initialEvents ?? const []) {
    logger.bind(detected: deviceStatus.events, isEnabled: settings.isEnabled);
    _storedSub = logger.onStored.listen(_handleStored);
    _lifecycle = AppLifecycleService(
      onEvent: (event) {
        logger.logEvent(
          type: event.type,
          description: event.description,
          metadata: event.metadata,
        );
      },
      onResumed: () {
        deviceStatus.recheckNetwork();
        deviceStatus.checkClock();
      },
    );
  }

  final EventLoggerService _logger;
  final LogStore _storage;
  final SettingsController _settings;
  final DeviceStatusController _device;
  final DateTime Function() _now;
  late final AppLifecycleService _lifecycle;
  StreamSubscription<LogEvent>? _storedSub;
  bool _loading;
  String? _loadError;
  bool _disposed = false;
  bool _launchLogged = false;
  bool _dashboardNoted = false;
  bool dashboardVisible = false;
  int skippedLines = 0;

  List<LogEvent> events;
  final List<LogEvent> sessionEvents = [];
  DateTime? sessionStartedAt;
  int sessionCount = 0;

  bool get isLogging => _logger.isLogging;
  bool get loading => _loading;
  String? get loadError => _loadError;

  Future<void> load() async {
    _loading = true;
    _loadError = null;
    notifyListeners();
    try {
      final result = await _storage.load();
      events = result.events;
      skippedLines = result.skipped;
    } catch (_) {
      _loadError = 'Unable to load logs.';
    } finally {
      _loading = false;
      if (!_disposed) {
        notifyListeners();
      }
    }
  }

  Future<void> reload() async {
    try {
      final result = await _storage.load();
      final byId = {for (final event in result.events) event.id: event};
      for (final event in events) {
        byId.putIfAbsent(event.id, () => event);
      }
      final merged = byId.values.toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      events = merged;
      skippedLines = result.skipped;
      _loadError = null;
    } catch (_) {
      _loadError = 'Unable to load logs.';
    }
    if (!_disposed) {
      notifyListeners();
    }
  }

  void attachLifecycle() {
    _lifecycle.attach();
  }

  Future<void> startLogging() async {
    if (_logger.isLogging || _disposed) {
      return;
    }
    sessionEvents.clear();
    sessionCount = 0;
    sessionStartedAt = _now();
    await _logger.startLogging();
    await _logger.logEvent(type: EventType.app, description: 'Logging started');
    if (!_launchLogged) {
      _launchLogged = true;
      await _logger.logEvent(
        type: EventType.app,
        description: 'Application launched',
      );
    }
    await _logBaseline();
    if (dashboardVisible) {
      await noteDashboardOpened();
    }
    await _settings.setLoggingEnabled(true);
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> stopLogging() async {
    if (!_logger.isLogging) {
      return;
    }
    await _logger.logEvent(type: EventType.app, description: 'Logging stopped');
    await _logger.stopLogging();
    await _settings.setLoggingEnabled(false);
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> noteDashboardOpened() async {
    if (!_logger.isLogging || _dashboardNoted) {
      return;
    }
    _dashboardNoted = true;
    await logAppAction('Dashboard opened');
  }

  void dashboardClosed() {
    dashboardVisible = false;
    _dashboardNoted = false;
  }

  Future<void> logAppAction(String description) async {
    await _logger.logEvent(type: EventType.app, description: description);
  }

  Future<void> clear() async {
    await _storage.clear();
    events = [];
    sessionEvents.clear();
    sessionCount = 0;
    skippedLines = 0;
    _loadError = null;
    if (!_disposed) {
      notifyListeners();
    }
  }

  String exportText() => renderAndroidLog(events, _now());

  Future<String> exportFile() async {
    final file = await _storage.writeExport(exportText());
    return file.path;
  }

  Future<void> _logBaseline() async {
    final battery = _device.battery;
    if (battery.level != null) {
      await _logger.logEvent(
        type: EventType.battery,
        description: 'Battery level is ${battery.level}%',
        metadata: {'batteryLevel': battery.level},
      );
    }
    final charging = ChargingService.baselineDescription(battery);
    if (charging != null) {
      await _logger.logEvent(
        type: EventType.charging,
        description: charging,
        metadata: {'charge': battery.charge.name},
      );
    }
    final network = _device.network;
    if (network != null) {
      await _logger.logEvent(
        type: EventType.network,
        description: NetworkService.transportLabel(network),
      );
      if (network.internetReachable != null) {
        await _logger.logEvent(
          type: EventType.network,
          description: network.internetReachable!
              ? 'Internet access available'
              : 'No internet access',
        );
      }
    }
    final screenOn = _device.screenOn;
    if (screenOn != null) {
      await _logger.logEvent(
        type: EventType.screen,
        description: screenOn ? 'Screen is on' : 'Screen is off',
      );
    }
  }

  void _handleStored(LogEvent event) {
    if (_disposed) {
      return;
    }
    events = [...events, event];
    if (_logger.isLogging) {
      sessionEvents.add(event);
      sessionCount += 1;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _storedSub?.cancel();
    _lifecycle.detach();
    _logger.dispose();
    super.dispose();
  }
}
