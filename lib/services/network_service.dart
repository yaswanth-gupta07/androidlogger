import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/detected_event.dart';
import '../models/device_snapshot.dart';
import '../models/event_type.dart';

abstract class InternetProbe {
  Future<bool> hasInternet();
}

/// Asks a public generate_204 endpoint whether this connection can reach
/// the internet. A Wi-Fi or mobile radio is not treated as proof of access.
class HttpInternetProbe implements InternetProbe {
  @override
  Future<bool> hasInternet() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 3);
    try {
      final request = await client
          .getUrl(
            Uri.parse('https://connectivitycheck.gstatic.com/generate_204'),
          )
          .timeout(const Duration(seconds: 4));
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      await response.drain<void>();
      return response.statusCode == 204 || response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }
}

class FakeInternetProbe implements InternetProbe {
  FakeInternetProbe({this.online = true});

  bool online;

  @override
  Future<bool> hasInternet() async => online;
}

abstract class ConnectivitySource {
  Future<List<ConnectivityResult>> check();
  Stream<List<ConnectivityResult>> get onChange;
}

class PluginConnectivitySource implements ConnectivitySource {
  PluginConnectivitySource({Connectivity? connectivity})
    : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  @override
  Future<List<ConnectivityResult>> check() => _connectivity.checkConnectivity();

  @override
  Stream<List<ConnectivityResult>> get onChange =>
      _connectivity.onConnectivityChanged;
}

class EmptyConnectivitySource implements ConnectivitySource {
  const EmptyConnectivitySource();

  @override
  Future<List<ConnectivityResult>> check() async => const [
    ConnectivityResult.none,
  ];

  @override
  Stream<List<ConnectivityResult>> get onChange => const Stream.empty();
}

Set<NetworkTransport> transportsFrom(List<ConnectivityResult> results) {
  if (results.isEmpty ||
      results.every((result) => result == ConnectivityResult.none)) {
    return {NetworkTransport.none};
  }
  final transports = <NetworkTransport>{};
  for (final result in results) {
    switch (result) {
      case ConnectivityResult.wifi:
        transports.add(NetworkTransport.wifi);
      case ConnectivityResult.mobile:
        transports.add(NetworkTransport.mobile);
      case ConnectivityResult.ethernet:
        transports.add(NetworkTransport.ethernet);
      case ConnectivityResult.vpn:
        transports.add(NetworkTransport.vpn);
      case ConnectivityResult.satellite:
        transports.add(NetworkTransport.satellite);
      case ConnectivityResult.bluetooth:
      case ConnectivityResult.other:
        transports.add(NetworkTransport.other);
      case ConnectivityResult.none:
        break;
    }
  }
  if (transports.isEmpty) {
    return {NetworkTransport.none};
  }
  return transports;
}

/// Watches connectivity changes and probes internet only after a change.
class NetworkService {
  NetworkService({
    required ConnectivitySource source,
    required InternetProbe probe,
  }) : _source = source,
       _probe = probe;

  final ConnectivitySource _source;
  final InternetProbe _probe;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  void Function(NetworkSnapshot snapshot)? _onUpdate;
  String? _transportLabel;
  bool? _internet;
  int _generation = 0;
  bool _started = false;

  Future<void> start(void Function(NetworkSnapshot snapshot) onUpdate) async {
    if (_started) {
      return;
    }
    _started = true;
    _onUpdate = onUpdate;
    try {
      await _publish(await _source.check());
    } catch (_) {
      onUpdate(
        const NetworkSnapshot.unavailable(
          error: 'Unable to read network status.',
        ),
      );
    }
    _subscription = _source.onChange.listen(
      (results) {
        _publish(results);
      },
      onError: (_) {
        _onUpdate?.call(
          const NetworkSnapshot.unavailable(
            error: 'Unable to read network status.',
          ),
        );
      },
    );
  }

  Future<void> recheck() async {
    if (!_started) {
      return;
    }
    try {
      await _publish(await _source.check());
    } catch (_) {
      _onUpdate?.call(
        const NetworkSnapshot.unavailable(
          error: 'Unable to read network status.',
        ),
      );
    }
  }

  Future<void> _publish(List<ConnectivityResult> results) async {
    final generation = ++_generation;
    final transports = transportsFrom(results);
    if (transports.contains(NetworkTransport.none)) {
      _onUpdate?.call(
        NetworkSnapshot(transports: transports, internetReachable: false),
      );
      return;
    }
    _onUpdate?.call(
      NetworkSnapshot(transports: transports, internetReachable: null),
    );
    final online = await _probe.hasInternet();
    if (generation != _generation) {
      return;
    }
    _onUpdate?.call(
      NetworkSnapshot(transports: transports, internetReachable: online),
    );
  }

  List<DetectedEvent> consume(NetworkSnapshot snapshot) {
    final events = <DetectedEvent>[];
    final label = transportLabel(snapshot);
    if (_transportLabel != null && label != _transportLabel) {
      events.add(
        DetectedEvent(
          type: EventType.network,
          description: label,
          metadata: {
            'transports': snapshot.transports
                .map((item) => item.name)
                .join(','),
          },
        ),
      );
    }
    _transportLabel = label;

    final internet = snapshot.internetReachable;
    if (internet != null && _internet != null && internet != _internet) {
      events.add(
        DetectedEvent(
          type: EventType.network,
          description: internet
              ? 'Internet access available'
              : 'No internet access',
        ),
      );
    }
    if (internet != null) {
      _internet = internet;
    }
    return events;
  }

  static String transportLabel(NetworkSnapshot snapshot) {
    final transports = snapshot.transports;
    if (transports.contains(NetworkTransport.wifi)) {
      return 'Wi-Fi connected';
    }
    if (transports.contains(NetworkTransport.ethernet)) {
      return 'Ethernet connected';
    }
    if (transports.contains(NetworkTransport.mobile)) {
      return 'Mobile network available';
    }
    if (transports.contains(NetworkTransport.satellite)) {
      return 'Satellite network available';
    }
    if (transports.contains(NetworkTransport.vpn)) {
      return 'VPN connected';
    }
    if (transports.contains(NetworkTransport.other)) {
      return 'Other network available';
    }
    return 'Network unavailable';
  }

  static String internetLabel(NetworkSnapshot snapshot) {
    if (snapshot.isOffline) {
      return 'No internet access';
    }
    return switch (snapshot.internetReachable) {
      true => 'Internet available',
      false => 'No internet access',
      null => 'Checking internet...',
    };
  }

  Future<void> dispose() async {
    _generation += 1;
    _started = false;
    await _subscription?.cancel();
    _subscription = null;
  }
}
