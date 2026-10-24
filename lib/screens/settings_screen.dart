import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/event_type.dart';
import '../providers/dropbox_provider.dart';
import '../providers/logging_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/date_time_utils.dart';
import '../widgets/dialogs.dart';
import 'dropbox_screen.dart';
import 'privacy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  static const route = '/settings';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<LoggingController>().logAppAction('Settings screen opened');
    });
  }

  Future<void> _export() async {
    final logging = context.read<LoggingController>();
    final messenger = ScaffoldMessenger.of(context);
    await logging.logAppAction('Log export started');
    try {
      final path = await logging.exportFile();
      if (!mounted) {
        return;
      }
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(path, mimeType: 'text/plain', name: 'android_log.txt')],
          subject: 'Android Logger',
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Unable to open the share sheet.')),
      );
    }
  }

  Future<void> _clear() async {
    final confirmed = await confirmAction(
      context,
      title: 'Clear logs',
      message: 'Delete every event stored on this device?',
      confirmLabel: 'Clear logs',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await context.read<LoggingController>().clear();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final logging = context.watch<LoggingController>();
    final dropbox = context.watch<DropboxController>();
    final theme = Theme.of(context);
    final lastSync = dropbox.status.lastSuccess;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Logging', style: theme.textTheme.titleMedium),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable logging'),
            subtitle: Text(
              logging.isLogging ? 'Logging active' : 'Logging stopped',
            ),
            value: logging.isLogging,
            onChanged: (enabled) {
              if (enabled) {
                logging.startLogging();
              } else {
                logging.stopLogging();
              }
            },
          ),
          const Text('Categories to record'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final type in EventType.values)
                FilterChip(
                  label: Text(type.label),
                  selected: settings.isEnabled(type),
                  onSelected: (selected) =>
                      settings.setCategoryEnabled(type, selected),
                ),
            ],
          ),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _clear, child: const Text('Clear logs')),
          const SizedBox(height: 24),
          Text('Appearance', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<ThemeMode>(
            segments: const [
              ButtonSegment(value: ThemeMode.light, label: Text('Light')),
              ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
              ButtonSegment(value: ThemeMode.system, label: Text('System')),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (selection) {
              settings.setThemeMode(selection.first);
            },
          ),
          const SizedBox(height: 24),
          Text('Dropbox', style: theme.textTheme.titleMedium),
          ListTile(
            key: const Key('openDropboxSettings'),
            contentPadding: EdgeInsets.zero,
            title: Text(dropbox.connected ? 'Connected' : 'Not connected'),
            subtitle: Text(
              lastSync == null
                  ? 'Last sync: Never'
                  : 'Last sync: ${formatClock(lastSync, withSeconds: false)}',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.pushNamed(context, DropboxScreen.route),
          ),
          const SizedBox(height: 16),
          Text('Storage', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          FilledButton.tonal(
            onPressed: _export,
            child: const Text('Export android_log.txt'),
          ),
          const SizedBox(height: 24),
          Text('About', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text('Android Logger ${settings.version}'),
          const SizedBox(height: 8),
          const Text(
            'Records supported device activity on this phone and can upload the log file to your Dropbox account.',
          ),
          TextButton(
            onPressed: () => Navigator.pushNamed(context, PrivacyScreen.route),
            child: const Text('Privacy information'),
          ),
        ],
      ),
    );
  }
}
