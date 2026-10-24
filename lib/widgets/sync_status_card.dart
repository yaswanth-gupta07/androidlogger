import 'package:flutter/material.dart';

import '../models/sync_status.dart';
import '../utils/date_time_utils.dart';
import '../utils/file_utils.dart';

class SyncStatusCard extends StatelessWidget {
  const SyncStatusCard({
    super.key,
    required this.connected,
    required this.status,
    required this.now,
  });

  final bool connected;
  final SyncStatus status;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = switch (status.phase) {
      SyncPhase.uploading => 'Uploading...',
      SyncPhase.success => 'Sync Complete',
      SyncPhase.failure => 'Sync Failed',
      SyncPhase.idle => connected ? 'Connected' : 'Not Connected',
    };
    final icon = switch (status.phase) {
      SyncPhase.success => Icons.check_circle_outline,
      SyncPhase.failure => Icons.error_outline,
      SyncPhase.uploading => Icons.cloud_upload_outlined,
      SyncPhase.idle => connected ? Icons.cloud_done_outlined : Icons.cloud_off,
    };
    final last = status.lastSuccess;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    connected ? '● $title' : '○ $title',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!connected && status.phase == SyncPhase.idle)
              const Text(
                'Connect your Dropbox account\nto synchronize your log file.',
              )
            else ...[
              const Text('Log File:'),
              const Text('android_log.txt'),
              const SizedBox(height: 8),
              const Text('File Size:'),
              Text(
                status.fileBytes == null
                    ? 'Not uploaded yet'
                    : formatBytes(status.fileBytes!),
              ),
              const SizedBox(height: 8),
              const Text('Last Sync:'),
              Text(
                last == null ? 'Never' : formatClock(last, withSeconds: false),
              ),
            ],
            if (status.phase == SyncPhase.uploading) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: status.progress == 0 ? null : status.progress,
              ),
              const SizedBox(height: 8),
              Text('${(status.progress * 100).round()}%'),
              const Text('android_log.txt'),
            ],
            if (status.message != null &&
                status.phase != SyncPhase.idle &&
                status.phase != SyncPhase.uploading) ...[
              const SizedBox(height: 12),
              Text(status.message!),
            ],
          ],
        ),
      ),
    );
  }
}
