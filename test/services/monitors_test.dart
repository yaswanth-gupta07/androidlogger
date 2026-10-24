import 'package:android_logger/models/device_snapshot.dart';
import 'package:android_logger/models/event_type.dart';
import 'package:android_logger/platform/system_event_source.dart';
import 'package:android_logger/services/app_lifecycle_service.dart';
import 'package:android_logger/services/audio_service.dart';
import 'package:android_logger/services/battery_service.dart';
import 'package:android_logger/services/charging_service.dart';
import 'package:android_logger/services/network_service.dart';
import 'package:android_logger/services/pkce.dart';
import 'package:android_logger/services/screen_state_service.dart';
import 'package:android_logger/services/time_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('battery and charging services log only real changes', () {
    final battery = BatteryService();
    final charging = ChargingService();
    const initial = BatterySnapshot(
      level: 82,
      charge: ChargeState.discharging,
      plug: 'none',
    );
    expect(battery.consume(initial), isEmpty);
    expect(battery.consume(initial), isEmpty);
    expect(charging.consume(initial), isEmpty);

    final level = battery.consume(
      const BatterySnapshot(
        level: 81,
        charge: ChargeState.discharging,
        plug: 'none',
      ),
    );
    expect(level.single.description, 'Battery level changed to 81%');
    expect(level.single.metadata['batteryLevel'], 81);

    final started = charging.consume(
      const BatterySnapshot(
        level: 81,
        charge: ChargeState.charging,
        plug: 'usb',
      ),
    );
    expect(
      started.map((event) => event.description),
      containsAll(['Charger connected', 'Charging started']),
    );
    expect(
      charging.consume(
        const BatterySnapshot(
          level: 81,
          charge: ChargeState.charging,
          plug: 'usb',
        ),
      ),
      isEmpty,
    );
    final stopped = charging.consume(
      const BatterySnapshot(
        level: 81,
        charge: ChargeState.discharging,
        plug: 'none',
      ),
    );
    expect(
      stopped.map((event) => event.description),
      containsAll(['Charger disconnected', 'Charging stopped']),
    );
  });

  test('network service separates radio changes from internet changes', () {
    final service = NetworkService(
      source: const EmptyConnectivitySource(),
      probe: FakeInternetProbe(),
    );
    final wifi = NetworkSnapshot(
      transports: transportsFrom(const [ConnectivityResult.wifi]),
      internetReachable: true,
    );
    expect(service.consume(wifi), isEmpty);
    expect(service.consume(wifi), isEmpty);
    expect(NetworkService.transportLabel(wifi), 'Wi-Fi connected');
    expect(NetworkService.internetLabel(wifi), 'Internet available');

    final lost = service.consume(const NetworkSnapshot.unavailable());
    expect(lost.map((event) => event.description), [
      'Network unavailable',
      'No internet access',
    ]);

    final mobile = service.consume(
      NetworkSnapshot(
        transports: transportsFrom(const [ConnectivityResult.mobile]),
        internetReachable: true,
      ),
    );
    expect(mobile.map((event) => event.description), [
      'Mobile network available',
      'Internet access available',
    ]);
  });

  test('screen, audio, and lifecycle services suppress duplicates', () {
    final screen = ScreenStateService(now: () => DateTime(2026, 10, 24, 13));
    expect(screen.consume('on'), isEmpty);
    expect(screen.consume('on'), isEmpty);
    expect(screen.consume('off').single.description, 'Screen turned off');
    expect(
      screen.consume('user_present').single.description,
      'User present after lock screen',
    );
    expect(screen.consume('user_present'), isEmpty);

    final audio = AudioService();
    expect(audio.consume(stream: 'media', volume: 4), isEmpty);
    expect(audio.consume(stream: 'media', volume: 4), isEmpty);
    final changed = audio.consume(stream: 'media', volume: 6, max: 15);
    expect(changed.single.description, 'Media volume changed');
    expect(changed.single.type, EventType.audio);
    expect(audio.consume(stream: 'notification', volume: 2), isEmpty);
    expect(
      audio.consume(stream: 'notification', volume: 3).single.description,
      'Notification volume changed',
    );

    final lifecycle = LifecycleInterpreter();
    expect(
      lifecycle.consume(AppLifecycleState.resumed)?.description,
      'Application resumed',
    );
    expect(lifecycle.consume(AppLifecycleState.resumed), isNull);
    expect(
      lifecycle.consume(AppLifecycleState.paused)?.description,
      'Application paused',
    );
  });

  test('time service logs clock, date, and zone changes only', () {
    var elapsed = Duration.zero;
    final service = TimeService(elapsed: () => elapsed);
    final start = DateTime(2026, 10, 24, 23);
    expect(service.poll(start), isEmpty);
    elapsed = const Duration(seconds: 30);
    expect(service.poll(start.add(elapsed)), isEmpty);

    elapsed = const Duration(minutes: 1);
    final jumped = service.poll(start.add(const Duration(minutes: 5)));
    expect(jumped.single.description, 'System time changed');

    final local = DateTime(2026, 10, 24, 13);
    if (local.timeZoneOffset != Duration.zero) {
      final zoned = TimeService(elapsed: () => Duration.zero)..baseline(local);
      expect(
        zoned.poll(local.toUtc()).map((event) => event.description),
        contains('Time zone changed'),
      );
    }

    var dayElapsed = Duration.zero;
    final dates = TimeService(elapsed: () => dayElapsed);
    dates.baseline(start);
    dayElapsed = const Duration(minutes: 61);
    expect(
      dates.poll(start.add(dayElapsed)).map((event) => event.description),
      ['Date changed'],
    );

    final broadcast = TimeService(elapsed: () => Duration.zero)
      ..baseline(start);
    expect(
      broadcast.onBroadcast('timezone', start).single.description,
      'Time zone changed',
    );
    expect(
      broadcast.onBroadcast('timezone', start.add(const Duration(seconds: 1))),
      isEmpty,
    );
    expect(
      broadcast
          .onBroadcast('date', start.add(const Duration(seconds: 6)))
          .single
          .description,
      'Date changed',
    );
  });

  test('pkce matches the RFC 7636 S256 vector', () {
    const verifier = 'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk';
    expect(
      PkcePair.challengeFor(verifier),
      'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
    );
    final pair = PkcePair.generate();
    expect(pair.verifier, isNot(pair.challenge));
    expect(pair.verifier.contains('='), isFalse);
    expect(pair.challenge.contains('='), isFalse);
  });

  test('native event maps parse without inventing values', () {
    final battery = parseSystemEvent({
      'kind': 'battery',
      'level': 82,
      'status': 'charging',
      'plug': 'usb',
    });
    expect(battery?.battery?.level, 82);
    expect(battery?.battery?.charge, ChargeState.charging);
    expect(
      parseSystemEvent({'kind': 'screen', 'state': 'off'})?.screen?.state,
      'off',
    );
    expect(
      parseSystemEvent({
        'kind': 'audio',
        'stream': 'ring',
        'volume': 3,
      })?.audio?.stream,
      'ring',
    );
    expect(
      parseSystemEvent({'kind': 'time', 'change': 'date'})?.time?.kind,
      'date',
    );
    expect(parseSystemEvent({'kind': 'keyboard'}), isNull);
    expect(normalizeLevel(120), isNull);
  });
}
