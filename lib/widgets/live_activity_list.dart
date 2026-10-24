import 'package:flutter/material.dart';

import '../models/log_event.dart';
import 'event_card.dart';
import 'state_views.dart';

class LiveActivityList extends StatelessWidget {
  const LiveActivityList({super.key, required this.events});

  final List<LogEvent> events;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final visible = events.reversed.take(15).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('LIVE ACTIVITY', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        if (visible.isEmpty)
          const EmptyState(
            message:
                'No events recorded yet.\n\nStart logging to see\nactivity here.',
          )
        else
          for (final event in visible) ...[
            EventCard(event: event, compact: true),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}
