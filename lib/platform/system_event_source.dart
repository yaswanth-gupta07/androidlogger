import 'dart:async';

import 'package:flutter/services.dart';

import '../models/device_snapshot.dart';

class ScreenSignal {
  const ScreenSignal(this.state);
  final String state;
}

class AudioSignal {
  const AudioSignal({
    required this.stream,
    required this.volume,
    this.previous,
    this.max,
  });

  final String stream;
  final int volume;
  final int? previous;
  final int? max;
}

class TimeSignal {
  const TimeSignal(this.kind);
  final String kind;
}

class ParsedSystemEvent {
  const ParsedSystemEvent({this.battery, this.screen, this.audio, this.time});

  final BatterySnapshot? battery;
  final ScreenSignal? screen;
  final AudioSignal? audio;
  final TimeSignal? time;
}

int? _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  return null;
}

int? normalizeLevel(int? level) {
  if (level == null || level < 0 || level > 100) {
    return null;
  }
  return level;
}

ChargeState chargeFromNative(String? status, String? plug) {
  return switch (status) {
    'charging' => ChargeState.charging,
    'full' => ChargeState.full,
    'discharging' => ChargeState.discharging,
    'not_charging' =>
      plug != null && plug != 'none'
          ? ChargeState.connectedNotCharging
          : ChargeState.notCharging,
    _ => ChargeState.unknown,
  };
}

Map<String, Object?> stringMap(Object? value) {
  if (value is! Map) {
    return {};
  }
  return value.map((key, item) => MapEntry(key.toString(), item));
}

Map<String, int> intMap(Object? value) {
  final result = <String, int>{};
  for (final entry in stringMap(value).entries) {
    final parsed = _asInt(entry.value);
    if (parsed != null) {
      result[entry.key] = parsed;
    }
  }
  return result;
}

ParsedSystemEvent? parseSystemEvent(Map<String, Object?> event) {
  switch (event['kind']) {
    case 'battery':
      return ParsedSystemEvent(
        battery: BatterySnapshot(
          level: normalizeLevel(_asInt(event['level'])),
          charge: chargeFromNative(
            event['status'] as String?,
            event['plug'] as String?,
          ),
          plug: event['plug'] as String?,
        ),
      );
    case 'screen':
      final state = event['state'];
      if (state is! String) {
        return null;
      }
      return ParsedSystemEvent(screen: ScreenSignal(state));
    case 'audio':
      final stream = event['stream'];
      final volume = _asInt(event['volume']);
      if (stream is! String || volume == null) {
        return null;
      }
      return ParsedSystemEvent(
        audio: AudioSignal(
          stream: stream,
          volume: volume,
          previous: _asInt(event['previous']),
          max: _asInt(event['max']),
        ),
      );
    case 'time':
      final kind = event['kindName'] ?? event['change'];
      if (kind is! String) {
        return null;
      }
      return ParsedSystemEvent(time: TimeSignal(kind));
    default:
      return null;
  }
}

SystemSnapshot parseSnapshot(Object? raw) {
  final map = stringMap(raw);
  final batteryMap = stringMap(map['battery']);
  BatterySnapshot? battery;
  if (batteryMap.isNotEmpty) {
    battery = BatterySnapshot(
      level: normalizeLevel(_asInt(batteryMap['level'])),
      charge: chargeFromNative(
        batteryMap['status'] as String?,
        batteryMap['plug'] as String?,
      ),
      plug: batteryMap['plug'] as String?,
    );
  }
  return SystemSnapshot(
    screenInteractive: map['screenInteractive'] as bool?,
    volumes: intMap(map['volumes']),
    volumeMax: intMap(map['maxVolumes']),
    timeZone: map['timeZone'] as String?,
    battery: battery,
  );
}

abstract class SystemEventSource {
  void start() {}
  Future<SystemSnapshot> snapshot();
  Stream<ParsedSystemEvent> get events;
  Future<void> dispose();
}

class EmptySystemEventSource implements SystemEventSource {
  const EmptySystemEventSource();

  @override
  void start() {}

  @override
  Future<SystemSnapshot> snapshot() async => SystemSnapshot.empty;

  @override
  Stream<ParsedSystemEvent> get events => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

class AndroidSystemEventSource implements SystemEventSource {
  AndroidSystemEventSource({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel(_methodName),
      _events = events ?? const EventChannel(_eventName);

  static const _methodName = 'com.example.android_logger/device_snapshot';
  static const _eventName = 'com.example.android_logger/device_events';

  final MethodChannel _methods;
  final EventChannel _events;
  final StreamController<ParsedSystemEvent> _controller =
      StreamController<ParsedSystemEvent>.broadcast();
  StreamSubscription<dynamic>? _subscription;
  bool _started = false;

  @override
  Stream<ParsedSystemEvent> get events => _controller.stream;

  @override
  Future<SystemSnapshot> snapshot() async {
    try {
      final raw = await _methods.invokeMethod<Object?>('snapshot');
      return parseSnapshot(raw);
    } catch (_) {
      return SystemSnapshot.empty;
    }
  }

  @override
  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _subscription = _events.receiveBroadcastStream().listen((event) {
      final parsed = parseSystemEvent(stringMap(event));
      if (parsed != null && !_controller.isClosed) {
        _controller.add(parsed);
      }
    }, onError: (_) {});
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
