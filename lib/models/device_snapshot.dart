/// Charging condition reported by Android or battery_plus.
enum ChargeState {
  charging,
  full,
  connectedNotCharging,
  discharging,
  notCharging,
  unknown,
}

/// A point-in-time battery reading. Null fields mean the source did not know.
class BatterySnapshot {
  const BatterySnapshot({
    this.level,
    this.charge = ChargeState.unknown,
    this.plug,
  });

  const BatterySnapshot.unknown() : this();

  final int? level;
  final ChargeState charge;
  final String? plug;

  bool get isKnown =>
      level != null || charge != ChargeState.unknown || plug != null;

  BatterySnapshot merge(BatterySnapshot next) {
    return BatterySnapshot(
      level: next.level ?? level,
      charge: next.charge == ChargeState.unknown ? charge : next.charge,
      plug: next.plug ?? plug,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is BatterySnapshot &&
        other.level == level &&
        other.charge == charge &&
        other.plug == plug;
  }

  @override
  int get hashCode => Object.hash(level, charge, plug);
}

enum NetworkTransport { wifi, mobile, ethernet, vpn, satellite, other, none }

/// Radio state plus a separate internet reachability result.
class NetworkSnapshot {
  const NetworkSnapshot({
    required this.transports,
    this.internetReachable,
    this.error,
  });

  const NetworkSnapshot.unavailable({this.error})
    : transports = const {NetworkTransport.none},
      internetReachable = false;

  final Set<NetworkTransport> transports;
  final bool? internetReachable;
  final String? error;

  bool get isOffline =>
      transports.isEmpty || transports.contains(NetworkTransport.none);

  bool get canReachInternet => !isOffline && internetReachable != false;

  @override
  bool operator ==(Object other) {
    return other is NetworkSnapshot &&
        other.internetReachable == internetReachable &&
        other.error == error &&
        other.transports.length == transports.length &&
        other.transports.containsAll(transports);
  }

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(transports), internetReachable, error);
}

/// Values read from Android without listening for later changes.
class SystemSnapshot {
  const SystemSnapshot({
    this.screenInteractive,
    this.volumes = const {},
    this.volumeMax = const {},
    this.timeZone,
    this.battery,
  });

  static const empty = SystemSnapshot();

  final bool? screenInteractive;
  final Map<String, int> volumes;
  final Map<String, int> volumeMax;
  final String? timeZone;
  final BatterySnapshot? battery;
}
