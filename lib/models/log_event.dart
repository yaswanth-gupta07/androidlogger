import 'dart:convert';

import '../utils/date_time_utils.dart';
import '../utils/file_utils.dart';
import 'event_type.dart';

/// One stored activity record.
class LogEvent {
  const LogEvent({
    required this.id,
    required this.timestamp,
    required this.type,
    required this.description,
    this.metadata = const {},
  });

  final String id;
  final DateTime timestamp;
  final EventType type;
  final String description;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'timestamp': toIsoOffset(timestamp),
      'type': type.name,
      'description': description,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  String toJsonLine() => jsonEncode(toJson());

  static LogEvent? tryParse(Object? raw) {
    if (raw is String) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        return tryParse(jsonDecode(trimmed));
      } on FormatException {
        return null;
      }
    }
    if (raw is! Map) {
      return null;
    }
    final json = raw.map((key, value) => MapEntry(key.toString(), value));
    final id = json['id'];
    final description = json['description'];
    final timestampRaw = json['timestamp'];
    final type = EventType.parse(json['type']);
    if (id is! String || id.trim().isEmpty || id.length > 200) {
      return null;
    }
    if (description is! String ||
        description.trim().isEmpty ||
        description.length > 2000) {
      return null;
    }
    if (timestampRaw is! String) {
      return null;
    }
    final timestamp = DateTime.tryParse(timestampRaw);
    if (timestamp == null || type == null) {
      return null;
    }
    final metadata = <String, Object?>{};
    final rawMetadata = json['metadata'];
    if (rawMetadata is Map) {
      for (final entry in rawMetadata.entries) {
        metadata[entry.key.toString()] = entry.value;
      }
    } else if (rawMetadata != null) {
      return null;
    }
    return LogEvent(
      id: id.trim(),
      timestamp: timestamp,
      type: type,
      description: description.trim(),
      metadata: sanitizeMetadata(metadata),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is LogEvent &&
        other.id == id &&
        other.timestamp.millisecondsSinceEpoch ==
            timestamp.millisecondsSinceEpoch &&
        other.type == type &&
        other.description == description &&
        metadataEquals(other.metadata, metadata);
  }

  @override
  int get hashCode => Object.hash(
    id,
    timestamp.millisecondsSinceEpoch,
    type,
    description,
    Object.hashAll(
      metadata.entries.map((entry) => Object.hash(entry.key, entry.value)),
    ),
  );
}
