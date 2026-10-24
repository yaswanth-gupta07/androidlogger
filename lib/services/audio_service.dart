import '../models/detected_event.dart';
import '../models/event_type.dart';

/// Records volume levels only. It never opens the microphone.
class AudioService {
  final Map<String, int> _levels = {};

  List<DetectedEvent> consume({
    required String stream,
    required int volume,
    int? max,
  }) {
    final previous = _levels[stream];
    _levels[stream] = volume;
    if (previous == null || previous == volume) {
      return const [];
    }
    return [
      DetectedEvent(
        type: EventType.audio,
        description: labelFor(stream),
        metadata: {
          'stream': stream,
          'volume': volume,
          'previous': previous,
          'max': ?max,
        },
      ),
    ];
  }

  static String labelFor(String stream) {
    return switch (stream) {
      'media' => 'Media volume changed',
      'notification' => 'Notification volume changed',
      'ring' => 'Ring volume changed',
      'alarm' => 'Alarm volume changed',
      _ => 'Volume changed',
    };
  }
}
