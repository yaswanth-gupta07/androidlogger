import 'package:flutter/material.dart';

import '../models/event_type.dart';

IconData iconForEvent(EventType type) {
  return switch (type) {
    EventType.battery => Icons.battery_charging_full,
    EventType.network => Icons.wifi,
    EventType.charging => Icons.power,
    EventType.app => Icons.phone_android,
    EventType.screen => Icons.smartphone,
    EventType.audio => Icons.volume_up,
    EventType.time => Icons.schedule,
  };
}
