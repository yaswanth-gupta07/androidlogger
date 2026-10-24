import '../models/detected_event.dart';
import '../models/event_type.dart';

/// Logs clock, date, and time-zone changes. It does not log every second.
class TimeService {
  TimeService({Duration Function()? elapsed}) : _elapsed = elapsed;

  final Duration Function()? _elapsed;
  final Stopwatch _watch = Stopwatch();
  DateTime? _wall;
  String? _zone;
  int? _offset;
  DateTime? _day;
  final Map<String, DateTime> _recent = {};

  void baseline(DateTime now) {
    _reset(now);
  }

  List<DetectedEvent> poll(DateTime now) {
    if (_wall == null) {
      _reset(now);
      return const [];
    }
    final events = <DetectedEvent>[];
    final expected = _wall!.add(_elapsed?.call() ?? _watch.elapsed);
    if (now.difference(expected).abs() > const Duration(seconds: 45)) {
      events.add(
        const DetectedEvent(
          type: EventType.time,
          description: 'System time changed',
        ),
      );
      _reset(now);
    }
    events.addAll(_calendarChanges(now));
    return _dedupe(events, now);
  }

  List<DetectedEvent> onBroadcast(String kind, DateTime now) {
    final description = switch (kind) {
      'time' => 'System time changed',
      'timezone' => 'Time zone changed',
      'date' => 'Date changed',
      _ => null,
    };
    _reset(now);
    if (description == null) {
      return const [];
    }
    return _dedupe([
      DetectedEvent(
        type: EventType.time,
        description: description,
        metadata: const {'source': 'broadcast'},
      ),
    ], now);
  }

  List<DetectedEvent> _calendarChanges(DateTime now) {
    final events = <DetectedEvent>[];
    final offset = now.timeZoneOffset.inMinutes;
    final zone = now.timeZoneName;
    final day = DateTime(now.year, now.month, now.day);
    if (_offset != null && (_offset != offset || _zone != zone)) {
      events.add(
        const DetectedEvent(
          type: EventType.time,
          description: 'Time zone changed',
        ),
      );
    }
    _offset = offset;
    _zone = zone;
    if (_day != null && _day != day) {
      events.add(
        const DetectedEvent(type: EventType.time, description: 'Date changed'),
      );
    }
    _day = day;
    return events;
  }

  List<DetectedEvent> _dedupe(List<DetectedEvent> events, DateTime now) {
    final kept = <DetectedEvent>[];
    for (final event in events) {
      final last = _recent[event.description];
      if (last != null && now.difference(last) < const Duration(seconds: 5)) {
        continue;
      }
      _recent[event.description] = now;
      kept.add(event);
    }
    return kept;
  }

  void _reset(DateTime now) {
    _wall = now;
    _watch
      ..reset()
      ..start();
    _zone = now.timeZoneName;
    _offset = now.timeZoneOffset.inMinutes;
    _day = DateTime(now.year, now.month, now.day);
  }
}
