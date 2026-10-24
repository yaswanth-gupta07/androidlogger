import 'package:flutter/material.dart';

class LoggingControl extends StatelessWidget {
  const LoggingControl({
    super.key,
    required this.isLogging,
    required this.syncing,
    required this.onStart,
    required this.onStop,
    required this.onViewLogs,
    required this.onSync,
  });

  final bool isLogging;
  final bool syncing;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback onViewLogs;
  final VoidCallback? onSync;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const Key('startLogging'),
                      onPressed: isLogging ? null : onStart,
                      child: const Text('Start Logging'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      key: const Key('stopLogging'),
                      onPressed: isLogging ? onStop : null,
                      child: const Text('Stop Logging'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      key: const Key('viewLogs'),
                      onPressed: onViewLogs,
                      child: const Text('View Logs'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      key: const Key('syncDropbox'),
                      onPressed: syncing ? null : onSync,
                      child: const Text('Sync to Dropbox'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
