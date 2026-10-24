import 'package:android_logger/models/event_type.dart';
import 'package:android_logger/models/log_event.dart';
import 'package:android_logger/utils/date_time_utils.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('serializes and deserializes a valid event', () {
    final event = LogEvent(
      id: 'event_001',
      timestamp: DateTime(2026, 10, 24, 13, 20, 30),
      type: EventType.battery,
      description: 'Battery level changed to 82%',
      metadata: const {'batteryLevel': 82},
    );

    final parsed = LogEvent.tryParse(event.toJson());

    expect(parsed, isNotNull);
    expect(parsed!.id, 'event_001');
    expect(parsed.type, EventType.battery);
    expect(parsed.description, 'Battery level changed to 82%');
    expect(parsed.metadata['batteryLevel'], 82);
    expect(formatLogStamp(parsed.timestamp), '2026-10-24 13:20:30');
    expect(
      event.toJson()['timestamp'],
      matches(RegExp(r'^2026-10-24T13:20:30[+-]\d{2}:\d{2}$')),
    );
    expect(parsed, isNot(equals(event.copyWithDifferentId())));
  });

  test('rejects invalid event payloads', () {
    expect(LogEvent.tryParse('not-json'), isNull);
    expect(LogEvent.tryParse(['nope']), isNull);
    expect(
      LogEvent.tryParse({
        'id': '',
        'timestamp': '2026-10-24T13:20:30+05:30',
        'type': 'battery',
        'description': 'Battery level changed to 82%',
      }),
      isNull,
    );
    expect(
      LogEvent.tryParse({
        'id': 'event_001',
        'timestamp': 'yesterday',
        'type': 'battery',
        'description': 'Battery level changed to 82%',
      }),
      isNull,
    );
    expect(
      LogEvent.tryParse({
        'id': 'event_001',
        'timestamp': '2026-10-24T13:20:30+05:30',
        'type': 'keylog',
        'description': 'nope',
      }),
      isNull,
    );
    expect(
      LogEvent.tryParse({
        'id': 'event_001',
        'timestamp': '2026-10-24T13:20:30+05:30',
        'type': 'battery',
        'description': '   ',
      }),
      isNull,
    );
  });

  test('strips secret-like metadata', () {
    final parsed = LogEvent.tryParse({
      'id': 'event_001',
      'timestamp': '2026-10-24T13:20:30+05:30',
      'type': 'BATTERY',
      'description': 'Battery level changed to 82%',
      'metadata': {
        'batteryLevel': 82,
        'access_token': 'secret',
        'password': 'nope',
      },
    });

    expect(parsed, isNotNull);
    expect(parsed!.metadata.containsKey('access_token'), isFalse);
    expect(parsed.metadata.containsKey('password'), isFalse);
    expect(parsed.metadata['batteryLevel'], 82);
  });

  test('parses every event type and rejects unknown names', () {
    expect(EventType.values, hasLength(7));
    expect(EventType.parse('network'), EventType.network);
    expect(EventType.parse('AUDIO'), EventType.audio);
    expect(EventType.parse('time'), EventType.time);
    expect(EventType.parse('keyboard'), isNull);
    expect(EventType.parse(null), isNull);
  });
}

extension on LogEvent {
  LogEvent copyWithDifferentId() {
    return LogEvent(
      id: '$id-other',
      timestamp: timestamp,
      type: type,
      description: description,
      metadata: metadata,
    );
  }
}
