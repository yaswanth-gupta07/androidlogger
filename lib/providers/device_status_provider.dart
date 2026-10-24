import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/detected_event.dart';
import '../models/device_snapshot.dart';
import '../platform/system_event_source.dart';
import '../services/audio_service.dart';
import '../services/battery_service.dart';
import '../services/charging_service.dart';
import '../services/network_service.dart';
import '../services/screen_state_service.dart';
import '../services/time_service.dart';

class DeviceStatusController extends ChangeNotifier {
  DeviceStatusController({
    required BatterySource battery,
    required NetworkService network,
    required SystemEventSource system,
    Duration? clockInterval = const Duration(seconds: 60),
    DateTime Function()? now,
    bool loading = true,
    String? initialError,
    BatterySnapshot? initialBattery,
    NetworkSnapshot? initialNetwork,
    bool? screenOn,
  }) : _batterySource = battery,
       _network = network,
       _system = system,
       _clockInterval = clockInterval,
       _now = now ?? DateTime.now,
       _loading = loading,
       _error = initialError,
       _battery = initialBattery ?? const BatterySnapshot.unknown(),
       _networkSnapshot = initialNetwork,
       _screenOn = screenOn {
    if (initialBattery != null) {
      _batteryTracker.consume(initialBattery);
      _charging.consume(initialBattery);
    }
    if (initialNetwork != null) {
      _network.consume(initialNetwork);
    }
    if (screenOn != null) {
      _screen.consume(screenOn ? 'on' : 'off');
    }
  }

  final BatterySource _batterySource;
  final NetworkService _network;
  final SystemEventSource _system;
  final Duration? _clockInterval;
  final DateTime Function() _now;
  final BatteryService _batteryTracker = BatteryService();
  final ChargingService _charging = ChargingService();
  final ScreenStateService _screen = ScreenStateService();
  final AudioService _audio = AudioService();
  final TimeService _time = TimeService();
  final StreamController<DetectedEvent> _detected =
      StreamController<DetectedEvent>.broadcast();

  StreamSubscription<BatterySnapshot>? _batterySub;
  StreamSubscription<ParsedSystemEvent>? _systemSub;
  Timer? _clock;
  bool _started = false;
  bool _disposed = false;
  bool _loading;
  String? _error;
  BatterySnapshot _battery;
  NetworkSnapshot? _networkSnapshot;
  bool? _screenOn;

  Stream<DetectedEvent> get events => _detected.stream;
  bool get loading => _loading;
  String? get error => _error;
  BatterySnapshot get battery => _battery;
  NetworkSnapshot? get network => _networkSnapshot;
  bool? get screenOn => _screenOn;
  bool get hasStatus => _battery.isKnown || _networkSnapshot != null;

  bool get offline => _networkSnapshot?.isOffline ?? false;

  bool get canSync {
    final snapshot = _networkSnapshot;
    if (snapshot == null || snapshot.isOffline) {
      return false;
    }
    return snapshot.internetReachable != false;
  }

  Future<void> start() async {
    if (_started || _disposed) {
      return;
    }
    _started = true;
    _loading = true;
    notifyListeners();
    try {
      final snapshot = await _system.snapshot();
      _applySystemSnapshot(snapshot);
      _system.start();
      _systemSub = _system.events.listen(_applySignal);
    } catch (_) {
      _error = 'Some device signals are unavailable.';
    }
    try {
      await _batterySource.start();
      _applyBattery(await _batterySource.readCurrent());
      _batterySub = _batterySource.changes.listen(_applyBattery);
    } catch (_) {
      _error ??= 'Unable to read battery status.';
    }
    try {
      await _network.start(_applyNetwork);
    } catch (_) {
      _error ??= 'Unable to read network status.';
      _networkSnapshot ??= const NetworkSnapshot.unavailable(
        error: 'Unable to read network status.',
      );
    }
    _time.baseline(_now());
    final interval = _clockInterval;
    if (interval != null) {
      _clock = Timer.periodic(interval, (_) => checkClock());
    }
    _loading = false;
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> retry() async {
    await _stopWatching();
    _started = false;
    _error = null;
    await start();
  }

  void checkClock() {
    _publish(_time.poll(_now()));
  }

  void recheckNetwork() {
    _network.recheck();
  }

  void _applySystemSnapshot(SystemSnapshot snapshot) {
    final battery = snapshot.battery;
    if (battery != null) {
      _applyBattery(battery);
    }
    final interactive = snapshot.screenInteractive;
    if (interactive != null) {
      _screenOn = interactive;
      _screen.consume(interactive ? 'on' : 'off');
    }
    for (final entry in snapshot.volumes.entries) {
      _audio.consume(stream: entry.key, volume: entry.value);
    }
  }

  void _applySignal(ParsedSystemEvent signal) {
    final battery = signal.battery;
    if (battery != null) {
      _applyBattery(battery);
    }
    final screen = signal.screen;
    if (screen != null) {
      if (screen.state == 'on' || screen.state == 'off') {
        _screenOn = screen.state == 'on';
      }
      _publish(_screen.consume(screen.state));
      notifyListeners();
    }
    final audio = signal.audio;
    if (audio != null) {
      _publish(
        _audio.consume(
          stream: audio.stream,
          volume: audio.volume,
          max: audio.max,
        ),
      );
    }
    final time = signal.time;
    if (time != null) {
      _publish(_time.onBroadcast(time.kind, _now()));
    }
  }

  void _applyBattery(BatterySnapshot incoming) {
    final merged = _battery.merge(incoming);
    final changed = merged != _battery;
    _battery = merged;
    _publish(_batteryTracker.consume(merged));
    _publish(_charging.consume(merged));
    if (changed && !_disposed) {
      notifyListeners();
    }
  }

  void _applyNetwork(NetworkSnapshot snapshot) {
    final changed = snapshot != _networkSnapshot;
    _networkSnapshot = snapshot;
    if (snapshot.error != null && _error == null) {
      _error = snapshot.error;
    }
    _publish(_network.consume(snapshot));
    if (changed && !_disposed) {
      notifyListeners();
    }
  }

  void _publish(List<DetectedEvent> events) {
    if (_detected.isClosed) {
      return;
    }
    for (final event in events) {
      _detected.add(event);
    }
  }

  Future<void> _stopWatching() async {
    _clock?.cancel();
    _clock = null;
    await _batterySub?.cancel();
    _batterySub = null;
    await _systemSub?.cancel();
    _systemSub = null;
    await _network.dispose();
  }

  @override
  void dispose() {
    _disposed = true;
    _clock?.cancel();
    _batterySub?.cancel();
    _systemSub?.cancel();
    _network.dispose();
    _batterySource.dispose();
    _system.dispose();
    _detected.close();
    super.dispose();
  }
}
