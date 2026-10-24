import '../models/detected_event.dart';
import '../models/device_snapshot.dart';
import '../models/event_type.dart';

/// Logs charger and charging transitions without repeating the same state.
class ChargingService {
  ChargeState? _charge;
  String? _plug;

  List<DetectedEvent> consume(BatterySnapshot snapshot) {
    final events = <DetectedEvent>[];
    final plug = snapshot.plug;
    if (plug != null && plug != _plug) {
      final previous = _plug;
      _plug = plug;
      if (previous != null) {
        if (previous == 'none' && plug != 'none') {
          events.add(
            DetectedEvent(
              type: EventType.charging,
              description: 'Charger connected',
              metadata: {'plug': plug},
            ),
          );
        } else if (previous != 'none' && plug == 'none') {
          events.add(
            const DetectedEvent(
              type: EventType.charging,
              description: 'Charger disconnected',
              metadata: {'plug': 'none'},
            ),
          );
        }
      }
    }

    if (snapshot.charge != ChargeState.unknown && snapshot.charge != _charge) {
      final previous = _charge;
      _charge = snapshot.charge;
      if (previous != null) {
        final description = _description(previous, snapshot.charge);
        if (description != null) {
          events.add(
            DetectedEvent(
              type: EventType.charging,
              description: description,
              metadata: {'charge': snapshot.charge.name},
            ),
          );
        }
      }
    }
    return events;
  }

  String? _description(ChargeState previous, ChargeState next) {
    return switch (next) {
      ChargeState.charging => 'Charging started',
      ChargeState.full => 'Battery fully charged',
      ChargeState.connectedNotCharging => 'Charger connected',
      ChargeState.discharging || ChargeState.notCharging =>
        _wasPowered(previous) ? 'Charging stopped' : null,
      ChargeState.unknown => null,
    };
  }

  bool _wasPowered(ChargeState state) {
    return state == ChargeState.charging ||
        state == ChargeState.full ||
        state == ChargeState.connectedNotCharging;
  }

  static String connectionLabel(BatterySnapshot snapshot) {
    final plugged = snapshot.plug != null && snapshot.plug != 'none';
    final powered =
        snapshot.charge == ChargeState.charging ||
        snapshot.charge == ChargeState.full ||
        snapshot.charge == ChargeState.connectedNotCharging;
    if (plugged || powered) {
      return 'Connected';
    }
    if (snapshot.charge == ChargeState.discharging ||
        snapshot.charge == ChargeState.notCharging ||
        snapshot.plug == 'none') {
      return 'Disconnected';
    }
    return 'Unknown';
  }

  static String stateLabel(BatterySnapshot snapshot) {
    return switch (snapshot.charge) {
      ChargeState.charging => 'Charging',
      ChargeState.full => 'Fully charged',
      ChargeState.connectedNotCharging => 'Connected, not charging',
      ChargeState.discharging || ChargeState.notCharging => 'Not charging',
      ChargeState.unknown => 'Unknown',
    };
  }

  static String? baselineDescription(BatterySnapshot snapshot) {
    if (!snapshot.isKnown) {
      return null;
    }
    return switch (snapshot.charge) {
      ChargeState.charging => 'Charging',
      ChargeState.full => 'Battery fully charged',
      ChargeState.connectedNotCharging => 'Charger connected',
      ChargeState.discharging || ChargeState.notCharging => 'Not charging',
      ChargeState.unknown =>
        snapshot.plug != null && snapshot.plug != 'none'
            ? 'Charger connected'
            : null,
    };
  }
}
