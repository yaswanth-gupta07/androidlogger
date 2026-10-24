String formatBytes(int bytes) {
  if (bytes < 0) {
    return '0 B';
  }
  if (bytes < 1024) {
    return '$bytes B';
  }
  final kilobytes = bytes / 1024;
  if (kilobytes < 1024) {
    final text = kilobytes >= 10
        ? kilobytes.toStringAsFixed(0)
        : kilobytes.toStringAsFixed(1);
    return '$text KB';
  }
  final megabytes = kilobytes / 1024;
  final text = megabytes >= 10
      ? megabytes.toStringAsFixed(0)
      : megabytes.toStringAsFixed(1);
  return '$text MB';
}

/// Removes metadata that must never be written to a log file.
Map<String, Object?> sanitizeMetadata(Map<String, Object?> input) {
  const blocked = <String>{
    'token',
    'access_token',
    'refresh_token',
    'password',
    'secret',
    'authorization',
    'code_verifier',
    'client_secret',
  };
  final sanitized = <String, Object?>{};
  for (final entry in input.entries) {
    final key = entry.key.trim();
    if (key.isEmpty || blocked.contains(key.toLowerCase())) {
      continue;
    }
    final value = entry.value;
    if (value == null || value is num || value is bool) {
      sanitized[key] = value;
    } else if (value is String && value.length <= 200) {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

bool metadataEquals(Map<String, Object?> left, Map<String, Object?> right) {
  if (left.length != right.length) {
    return false;
  }
  for (final key in left.keys) {
    if (!right.containsKey(key) || left[key] != right[key]) {
      return false;
    }
  }
  return true;
}
