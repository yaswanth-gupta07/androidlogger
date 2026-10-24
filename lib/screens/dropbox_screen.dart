import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/dropbox_config.dart';
import '../models/sync_status.dart';
import '../providers/dropbox_provider.dart';
import '../providers/logging_provider.dart';
import '../services/dropbox_api.dart';
import '../widgets/dialogs.dart';
import '../widgets/sync_status_card.dart';

class DropboxScreen extends StatefulWidget {
  const DropboxScreen({super.key});

  static const route = '/dropbox';

  @override
  State<DropboxScreen> createState() => _DropboxScreenState();
}

class _DropboxScreenState extends State<DropboxScreen> {
  late final TextEditingController _appKey;
  final TextEditingController _code = TextEditingController();
  var _syncRequested = false;

  @override
  void initState() {
    super.initState();
    _appKey = TextEditingController(
      text: context.read<DropboxController>().appKey,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _afterFirstFrame());
  }

  Future<void> _afterFirstFrame() async {
    if (!mounted) {
      return;
    }
    context.read<LoggingController>().logAppAction('Dropbox screen opened');
    final arguments = ModalRoute.of(context)?.settings.arguments;
    if (arguments == 'sync' && !_syncRequested) {
      _syncRequested = true;
      await _sync();
    }
  }

  @override
  void dispose() {
    _appKey.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _saveKey() async {
    final error = await context.read<DropboxController>().saveAppKey(
      _appKey.text,
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(error ?? 'App key saved on this device.')),
    );
  }

  Future<void> _connect() async {
    final dropbox = context.read<DropboxController>();
    final error = await dropbox.saveAppKey(_appKey.text);
    if (!mounted) {
      return;
    }
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    await dropbox.connect();
  }

  Future<void> _manual() async {
    final dropbox = context.read<DropboxController>();
    final messenger = ScaffoldMessenger.of(context);
    final error = await dropbox.saveAppKey(_appKey.text);
    if (!mounted) {
      return;
    }
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
      return;
    }
    try {
      final uri = await dropbox.beginManualConnect();
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Unable to open the Dropbox sign-in page.'),
          ),
        );
      }
    } on DropboxException catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  Future<void> _submitCode() async {
    await context.read<DropboxController>().completeManualConnect(_code.text);
    if (mounted) {
      _code.clear();
    }
  }

  Future<void> _sync() async {
    final logging = context.read<LoggingController>();
    final dropbox = context.read<DropboxController>();
    await logging.logAppAction('Dropbox sync started');
    final ok = await dropbox.syncNow();
    await logging.logAppAction(
      ok ? 'Dropbox sync completed' : 'Dropbox sync failed',
    );
  }

  Future<void> _disconnect() async {
    final confirmed = await confirmAction(
      context,
      title: 'Disconnect Dropbox',
      message: 'Remove the saved Dropbox session from this device?',
      confirmLabel: 'Disconnect',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await context.read<DropboxController>().disconnect();
  }

  @override
  Widget build(BuildContext context) {
    final dropbox = context.watch<DropboxController>();
    final status = dropbox.status;
    return Scaffold(
      appBar: AppBar(title: const Text('Dropbox')),
      body: ListView(
        key: const Key('dropboxList'),
        padding: const EdgeInsets.all(16),
        children: [
          SyncStatusCard(
            connected: dropbox.connected,
            status: status,
            now: DateTime.now(),
          ),
          const SizedBox(height: 16),
          Text(
            'Uploads replace ${DropboxConfig.uploadPath}. With App folder access, Dropbox stores that file inside the app folder.',
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('dropboxAppKey'),
            controller: _appKey,
            decoration: const InputDecoration(
              labelText: 'Dropbox app key',
              helperText: 'Public app key only. Do not enter an access token.',
            ),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _saveKey,
              child: const Text('Save app key'),
            ),
          ),
          SelectableText('Redirect URI: ${DropboxConfig.redirectUri}'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () async {
                await Clipboard.setData(
                  const ClipboardData(text: DropboxConfig.redirectUri),
                );
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Redirect URI copied.')),
                );
              },
              child: const Text('Copy redirect URI'),
            ),
          ),
          const SizedBox(height: 8),
          if (!dropbox.connected)
            FilledButton(
              key: const Key('dropboxConnect'),
              onPressed: dropbox.busy ? null : _connect,
              child: const Text('Connect Dropbox'),
            )
          else ...[
            FilledButton(
              key: const Key('syncNow'),
              onPressed: dropbox.busy || status.isUploading ? null : _sync,
              child: const Text('Sync Now'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              key: const Key('dropboxDisconnect'),
              onPressed: dropbox.busy ? null : _disconnect,
              child: const Text('Disconnect'),
            ),
          ],
          if (status.phase == SyncPhase.failure) ...[
            const SizedBox(height: 8),
            FilledButton.tonal(
              key: const Key('syncRetry'),
              onPressed: dropbox.connected && !dropbox.busy ? _sync : _connect,
              child: const Text('Retry'),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            'Use a code instead',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          const Text(
            'If the browser does not return to Android Logger, open Dropbox and paste the authorization code it shows. The code is exchanged with PKCE. It is not stored in the log.',
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: dropbox.busy ? null : _manual,
            child: const Text('Open Dropbox code page'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('manualCode'),
            controller: _code,
            decoration: const InputDecoration(labelText: 'Authorization code'),
            autocorrect: false,
            enableSuggestions: false,
          ),
          const SizedBox(height: 8),
          FilledButton.tonal(
            key: const Key('submitCode'),
            onPressed: dropbox.busy ? null : _submitCode,
            child: const Text('Submit code'),
          ),
        ],
      ),
    );
  }
}
