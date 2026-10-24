import 'dart:io';

import '../models/event_type.dart';
import '../models/log_event.dart';
import '../utils/date_time_utils.dart';

class LoadResult {
  const LoadResult({required this.events, this.skipped = 0});

  final List<LogEvent> events;
  final int skipped;
}

class LogQuery {
  const LogQuery({this.text = '', this.types = const {}, this.day});

  final String text;
  final Set<EventType> types;
  final DateTime? day;
}

/// Filters events in memory. Storage search uses the same rules.
class LogFilter {
  static String _searchText(String value) {
    return value.toLowerCase().replaceAll('-', '');
  }

  static List<LogEvent> apply(List<LogEvent> events, LogQuery query) {
    final text = query.text.trim().toLowerCase();
    return events.where((event) {
      if (query.types.isNotEmpty && !query.types.contains(event.type)) {
        return false;
      }
      if (query.day != null && !isSameDay(event.timestamp, query.day!)) {
        return false;
      }
      if (text.isEmpty) {
        return true;
      }
      final stamp = formatLogStamp(event.timestamp);
      final iso = toIsoOffset(event.timestamp);
      final haystack = _searchText(
        '${event.description} ${event.type.name} ${event.type.label} $stamp $iso',
      );
      return haystack.contains(_searchText(text));
    }).toList();
  }
}

/// Builds the readable `android_log.txt` export.
String renderAndroidLog(List<LogEvent> events, DateTime generatedAt) {
  final buffer = StringBuffer()
    ..writeln('ANDROID LOGGER')
    ..writeln('Generated: ${formatLongDate(generatedAt)}')
    ..writeln()
    ..writeln('------------------------------------------------')
    ..writeln();
  if (events.isEmpty) {
    buffer.writeln('No events recorded.');
    return buffer.toString();
  }
  for (var index = 0; index < events.length; index++) {
    final event = events[index];
    buffer
      ..writeln(formatLogStamp(event.timestamp))
      ..writeln(event.type.label)
      ..writeln(event.description);
    final keys = event.metadata.keys.toList()..sort();
    for (final key in keys) {
      buffer.writeln('$key: ${event.metadata[key]}');
    }
    if (index != events.length - 1) {
      buffer.writeln();
    }
  }
  if (!buffer.toString().endsWith('\n')) {
    buffer.writeln();
  }
  return buffer.toString();
}

abstract class LogStore {
  Future<LoadResult> load();
  Future<void> append(LogEvent event);
  Future<void> clear();
  Future<List<LogEvent>> search(LogQuery query);
  Future<File> writeExport(String contents);
}

/// JSON Lines file in application-private storage.
class LogStorageService implements LogStore {
  LogStorageService(this.directory);

  final Directory directory;
  Future<void> _tail = Future<void>.value();

  File get _eventsFile => File('${directory.path}/events.jsonl');
  File get exportFile => File('${directory.path}/android_log.txt');

  Future<T> _serialized<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  @override
  Future<LoadResult> load() {
    return _serialized(() async {
      final file = _eventsFile;
      if (!await file.exists()) {
        return const LoadResult(events: []);
      }
      final content = await file.readAsString();
      final events = <LogEvent>[];
      var skipped = 0;
      for (final line in content.split(RegExp(r'\r?\n'))) {
        if (line.trim().isEmpty) {
          continue;
        }
        final event = LogEvent.tryParse(line);
        if (event == null) {
          skipped += 1;
        } else {
          events.add(event);
        }
      }
      return LoadResult(events: events, skipped: skipped);
    });
  }

  @override
  Future<void> append(LogEvent event) {
    return _serialized(() async {
      await directory.create(recursive: true);
      await _eventsFile.writeAsString(
        '${event.toJsonLine()}\n',
        mode: FileMode.append,
        flush: true,
      );
    });
  }

  @override
  Future<void> clear() {
    return _serialized(() async {
      final file = _eventsFile;
      if (await file.exists()) {
        await file.delete();
      }
    });
  }

  @override
  Future<List<LogEvent>> search(LogQuery query) async {
    final loaded = await load();
    return LogFilter.apply(loaded.events, query);
  }

  @override
  Future<File> writeExport(String contents) {
    return _serialized(() async {
      await directory.create(recursive: true);
      await exportFile.writeAsString(contents, flush: true);
      return exportFile;
    });
  }
}

/// In-memory store used by widget tests. Export still writes a real temp file.
class MemoryLogStorage implements LogStore {
  MemoryLogStorage(this.directory);

  final Directory directory;
  final List<LogEvent> _events = [];

  @override
  Future<LoadResult> load() async => LoadResult(events: List.of(_events));

  @override
  Future<void> append(LogEvent event) async {
    _events.add(event);
  }

  @override
  Future<void> clear() async {
    _events.clear();
  }

  @override
  Future<List<LogEvent>> search(LogQuery query) async {
    return LogFilter.apply(_events, query);
  }

  @override
  Future<File> writeExport(String contents) async {
    await directory.create(recursive: true);
    final file = File('${directory.path}/android_log.txt');
    await file.writeAsString(contents, flush: true);
    return file;
  }
}
