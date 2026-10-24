import 'package:flutter/material.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const route = '/privacy';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('What is collected', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'While logging is on, Android Logger can store battery level, charging state, network type, whether an internet check succeeded, this app\'s own lifecycle, screen on/off, the Android "user present" signal, volume levels, and system time, date, or time-zone changes.',
          ),
          const SizedBox(height: 16),
          Text('What is not collected', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'The app does not record keystrokes, passwords, messages, call or SMS content, microphone audio, conversations, photos, or activity inside other apps. It does not use an Accessibility Service.',
          ),
          const SizedBox(height: 16),
          Text('Why events are logged', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'The log is a personal record of device state that you can review, export, or upload. Logging starts only after you choose Start Logging, and you can stop it at any time.',
          ),
          const SizedBox(height: 16),
          Text('Where data is stored', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Events stay in a private file inside this app\'s storage. The readable export is android_log.txt in that same private folder. Other apps cannot read it unless you share it.',
          ),
          const SizedBox(height: 16),
          Text('When data is uploaded', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Nothing is uploaded until you press Sync. The upload replaces /android_log.txt. If the network is unavailable, the local log is kept.',
          ),
          const SizedBox(height: 16),
          Text('Dropbox access', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Sign-in uses OAuth 2.0 with PKCE. The app asks only for permission to write files. The access token and refresh token are stored in encrypted storage. The app key is a public client id, not a password. Disconnect deletes the session from this device and asks Dropbox to revoke it.',
          ),
          const SizedBox(height: 16),
          Text('Deleting logs', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Clear logs in Settings or on the Logs screen deletes the local history. It does not delete a copy already stored in Dropbox. You can remove that file from Dropbox yourself.',
          ),
          const SizedBox(height: 16),
          Text('Limits you should know', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Screen, volume, and time signals are observed only while this app\'s process is running. Android does not let a normal app watch the inside of other apps, and this app does not try to bypass that. A connected network is not treated as proof of internet access.',
          ),
        ],
      ),
    );
  }
}
