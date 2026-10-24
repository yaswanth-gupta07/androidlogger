import 'dart:async';

import 'package:battery_plus/battery_plus.dart';

import '../models/detected_event.dart';
import '../models/device_snapshot.dart';
import '../models/event_type.dart';

/// Remembers the last percentage and emits a log only when it changes.
class BatteryService {
  int? _level;

  List<DetectedEvent> consume(BatterySnapshot snapshot) {
    final level = snapshot.level;
    if (level == null) {
      return const [];
    }
    final previous = _level;
    _level = level;
    if (previous == null || previous == level) {
      return const [];
    }
    return [
      DetectedEvent(
        type: EventType.battery,
        description: 'Battery level changed to $level%',
        metadata: {'batteryLevel': level, 'previousLevel': previous},
      ),
    ];
  }
}

abstract class BatterySource {
  Future<void> start() async {}
  Future<BatterySnapshot> readCurrent();
  Stream<BatterySnapshot> get changes;
  Future<void> dispose();
}

class EmptyBatterySource implements BatterySource {
  const EmptyBatterySource();

  @override
  Future<void> start() async {}

  @override
  Future<BatterySnapshot> readCurrent() async =>
      const BatterySnapshot.unknown();

  @override
  Stream<BatterySnapshot> get changes => const Stream.empty();

  @override
  Future<void> dispose() async {}
}

ChargeState chargeStateFromPlugin(BatteryState state) {
  return switch (state) {
    BatteryState.charging => ChargeState.charging,
    BatteryState.full => ChargeState.full,
    BatteryState.connectedNotCharging => ChargeState.connectedNotCharging,
    BatteryState.discharging => ChargeState.discharging,
    BatteryState.unknown => ChargeState.unknown,
  };
}

/// Reads battery_plus and polls the level because the plugin streams state,
/// not every percentage change. Android broadcasts supply the timely updates.
class BatteryPlusSource implements BatterySource {
  BatteryPlusSource({
    Battery? battery,
    this.pollInterval = const Duration(seconds: 60),
  }) : _battery = battery ?? Battery();

  final Battery _battery;
  final Duration pollInterval;
  final StreamController<BatterySnapshot> _controller =
      StreamController<BatterySnapshot>.broadcast();
  StreamSubscription<BatteryState>? _stateSub;
  Timer? _poll;
  bool _started = false;

  @override
  Stream<BatterySnapshot> get changes => _controller.stream;

  @override
  Future<BatterySnapshot> readCurrent() async {
    try {
      final level = await _battery.batteryLevel.timeout(
        const Duration(seconds: 4),
      );
      final state = await _battery.batteryState.timeout(
        const Duration(seconds: 4),
      );
      return BatterySnapshot(
        level: level >= 0 && level <= 100 ? level : null,
        charge: chargeStateFromPlugin(state),
      );
    } catch (_) {
      return const BatterySnapshot.unknown();
    }
  }

  @override
  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;
    _stateSub = _battery.onBatteryStateChanged.listen((state) {
      if (!_controller.isClosed) {
        _controller.add(BatterySnapshot(charge: chargeStateFromPlugin(state)));
      }
    }, onError: (_) {});
    _poll = Timer.periodic(pollInterval, (_) => _pollLevel());
  }

  Future<void> _pollLevel() async {
    final snapshot = await readCurrent();
    if (!_controller.isClosed && snapshot.level != null) {
      _controller.add(snapshot);
    }
  }

  @override
  Future<void> dispose() async {
    _poll?.cancel();
    await _stateSub?.cancel();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}
