import 'package:flutter/material.dart';

import '../models/log_event.dart';
import '../utils/date_time_utils.dart';
import 'event_style.dart';

class EventCard extends StatelessWidget {
  const EventCard({super.key, required this.event, this.compact = false});

  final LogEvent event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = iconForEvent(event.type);
    final time = compact
        ? formatClock(event.timestamp)
        : formatShortDate(event.timestamp);
    return Semantics(
      label:
          '${event.type.title}. ${event.description}. ${formatLogStamp(event.timestamp)}',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compact)
                      Text(time, style: theme.textTheme.labelLarge)
                    else
                      Text(event.type.label, style: theme.textTheme.labelLarge),
                    const SizedBox(height: 4),
                    Text(
                      compact ? event.type.title : event.description,
                      style: theme.textTheme.titleSmall,
                    ),
                    if (compact) ...[
                      const SizedBox(height: 2),
                      Text(event.description),
                    ] else ...[
                      const SizedBox(height: 8),
                      Text(formatShortDate(event.timestamp)),
                      Text(formatClock(event.timestamp)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
