import 'dart:async';
import 'dart:io';

import 'package:android_logger/models/detected_event.dart';
import 'package:android_logger/models/event_type.dart';
import 'package:android_logger/models/log_event.dart';
import 'package:android_logger/services/event_logger_service.dart';
import 'package:android_logger/services/log_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

LogEvent sample(String id, EventType type, String description) {
  return LogEvent(
    id: id,
    timestamp: DateTime(2026, 10, 24, 13, 20, 30),
    type: type,
    description: description,
  );
}

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('android_logger_test');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('saves, appends, reads, searches, and clears events', () async {
    final storage = LogStorageService(directory);
    expect((await storage.load()).events, isEmpty);

    await storage.append(
      sample('1', EventType.battery, 'Battery level changed to 82%'),
    );
    await storage.append(sample('2', EventType.network, 'Wi-Fi connected'));
    await _eventsFileLine(directory, '{"id":"bad","type":"nope"}\n');

    final loaded = await storage.load();
    expect(loaded.events.map((event) => event.id), ['1', '2']);
    expect(loaded.skipped, 1);

    final found = await storage.search(
      const LogQuery(text: 'wifi', types: {EventType.network}),
    );
    expect(found, hasLength(1));
    expect(found.single.description, 'Wi-Fi connected');

    final exported = renderAndroidLog(loaded.events, DateTime(2026, 10, 24));
    expect(exported, contains('ANDROID LOGGER'));
    expect(exported, contains('Generated: 24 October 2026'));
    expect(exported, contains('BATTERY'));
    expect(exported, contains('Battery level changed to 82%'));
    expect(exported, isNot(contains('access_token')));

    final file = await storage.writeExport(exported);
    expect(file.path, endsWith('android_log.txt'));
    expect(await file.readAsString(), exported);

    await storage.clear();
    expect((await storage.load()).events, isEmpty);
    expect(
      renderAndroidLog(const [], DateTime(2026, 10, 24)),
      contains('No events recorded.'),
    );
  });

  test(
    'logger starts once, stores events, and ignores events while stopped',
    () async {
      final storage = MemoryLogStorage(directory);
      final logger = EventLoggerService(
        storage: storage,
        now: () => DateTime(2026, 10, 24, 13, 20, 30),
      );
      final detected = StreamController<DetectedEvent>.broadcast();
      logger.bind(detected: detected.stream, isEnabled: (_) => true);
      logger.bind(detected: detected.stream, isEnabled: (_) => true);

      expect(
        await logger.logEvent(type: EventType.app, description: 'Ignored'),
        isNull,
      );

      await logger.startLogging();
      await logger.startLogging();
      final stored = await logger.logEvent(
        type: EventType.battery,
        description: 'Battery level changed to 82%',
        metadata: const {'batteryLevel': 82, 'access_token': 'hidden'},
      );
      final streamed = logger.onStored.first;
      detected.add(
        const DetectedEvent(
          type: EventType.network,
          description: 'Wi-Fi connected',
        ),
      );
      await streamed;
      await logger.stopLogging();
      await logger.logEvent(type: EventType.app, description: 'After stop');

      final events = (await storage.load()).events;
      expect(stored, isNotNull);
      expect(events.map((event) => event.description), [
        'Battery level changed to 82%',
        'Wi-Fi connected',
      ]);
      expect(events.first.metadata.containsKey('access_token'), isFalse);
      expect(logger.acceptedCount, 2);
      await detected.close();
      await logger.dispose();
    },
  );
}

Future<void> _eventsFileLine(Directory directory, String line) {
  return File(
    '${directory.path}/events.jsonl',
  ).writeAsString(line, mode: FileMode.append);
}
