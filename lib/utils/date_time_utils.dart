const _months = <String>[
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _shortMonths = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String twoDigits(int value) => value.toString().padLeft(2, '0');

/// ISO-8601 local timestamp with a numeric offset, such as `+05:30`.
String toIsoOffset(DateTime time) {
  final local = time.toLocal();
  final offset = local.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absolute = offset.abs();
  final hours = twoDigits(absolute.inHours);
  final minutes = twoDigits(absolute.inMinutes.remainder(60));
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}'
      'T${twoDigits(local.hour)}:${twoDigits(local.minute)}:'
      '${twoDigits(local.second)}$sign$hours:$minutes';
}

/// `2026-10-24 13:20:30` in the local time zone.
String formatLogStamp(DateTime time) {
  final local = time.toLocal();
  return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
      '${twoDigits(local.hour)}:${twoDigits(local.minute)}:'
      '${twoDigits(local.second)}';
}

/// `13:20:30`
String formatClock(DateTime time, {bool withSeconds = true}) {
  final local = time.toLocal();
  final hours = '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  if (!withSeconds) {
    return hours;
  }
  return '$hours:${twoDigits(local.second)}';
}

/// `24 October 2026`
String formatLongDate(DateTime time) {
  final local = time.toLocal();
  return '${local.day} ${_months[local.month - 1]} ${local.year}';
}

/// `24 Oct 2026`
String formatShortDate(DateTime time) {
  final local = time.toLocal();
  return '${local.day} ${_shortMonths[local.month - 1]} ${local.year}';
}

bool isSameDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String relativeTime(DateTime time, DateTime now) {
  var delta = now.difference(time);
  if (delta.isNegative) {
    delta = Duration.zero;
  }
  if (delta.inSeconds < 10) {
    return 'just now';
  }
  if (delta.inMinutes < 1) {
    return '${delta.inSeconds} seconds ago';
  }
  if (delta.inHours < 1) {
    final minutes = delta.inMinutes;
    return '$minutes ${minutes == 1 ? 'minute' : 'minutes'} ago';
  }
  if (delta.inDays < 1) {
    final hours = delta.inHours;
    return '$hours ${hours == 1 ? 'hour' : 'hours'} ago';
  }
  final days = delta.inDays;
  return '$days ${days == 1 ? 'day' : 'days'} ago';
}

String startedLabel(DateTime start, DateTime now) {
  final relative = relativeTime(start, now);
  if (relative == 'just now') {
    return 'Started just now';
  }
  return 'Started $relative';
}
