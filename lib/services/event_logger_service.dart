import 'dart:async';
import 'dart:developer' as developer;

import '../models/detected_event.dart';
import '../models/event_type.dart';
import '../models/log_event.dart';
import '../utils/file_utils.dart';
import 'log_storage_service.dart';

/// Stores activity while a logging session is running.
///
/// Device subscriptions are attached once through [bind]. Calling [bind] or
/// [startLogging] again does not add another listener.
class EventLoggerService {
  EventLoggerService({required LogStore storage, DateTime Function()? now})
    : _storage = storage,
      _now = now ?? DateTime.now;

  final LogStore _storage;
  final DateTime Function() _now;
  final StreamController<LogEvent> _stored =
      StreamController<LogEvent>.broadcast();

  StreamSubscription<DetectedEvent>? _detectedSub;
  bool Function(EventType type)? _isEnabled;
  bool _active = false;
  bool _bound = false;
  int _counter = 0;
  int _accepted = 0;

  bool get isLogging => _active;
  int get acceptedCount => _accepted;
  Stream<LogEvent> get onStored => _stored.stream;

  /// Listens to interpreted device events. Safe to call more than once.
  void bind({
    required Stream<DetectedEvent> detected,
    required bool Function(EventType type) isEnabled,
  }) {
    if (_bound) {
      return;
    }
    _bound = true;
    _isEnabled = isEnabled;
    _detectedSub = detected.listen((event) async {
      try {
        await logEvent(
          type: event.type,
          description: event.description,
          metadata: event.metadata,
        );
      } catch (error, stackTrace) {
        developer.log(
          'Unable to record a device event',
          name: 'logger',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
  }

  Future<void> startLogging() async {
    if (_active) {
      return;
    }
    _active = true;
  }

  Future<void> stopLogging() async {
    _active = false;
  }

  Future<LogEvent?> logEvent({
    required EventType type,
    required String description,
    Map<String, Object?> metadata = const {},
  }) async {
    if (!_active) {
      return null;
    }
    if (_isEnabled != null && !_isEnabled!(type)) {
      return null;
    }
    final cleanDescription = description.trim();
    if (cleanDescription.isEmpty) {
      return null;
    }
    _counter += 1;
    final event = LogEvent(
      id: 'event_${_now().microsecondsSinceEpoch}_$_counter',
      timestamp: _now(),
      type: type,
      description: cleanDescription,
      metadata: sanitizeMetadata(metadata),
    );
    try {
      await _storage.append(event);
    } catch (error, stackTrace) {
      developer.log(
        'Unable to store an event',
        name: 'logger',
        error: error,
        stackTrace: stackTrace,
      );
      return null;
    }
    _accepted += 1;
    if (!_stored.isClosed) {
      _stored.add(event);
    }
    return event;
  }

  Future<void> dispose() async {
    await _detectedSub?.cancel();
    _detectedSub = null;
    _bound = false;
    if (!_stored.isClosed) {
      await _stored.close();
    }
  }
}
