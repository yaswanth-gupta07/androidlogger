import 'event_type.dart';

/// A device or application change before it is stored.
class DetectedEvent {
  const DetectedEvent({
    required this.type,
    required this.description,
    this.metadata = const {},
  });

  final EventType type;
  final String description;
  final Map<String, Object?> metadata;
}
