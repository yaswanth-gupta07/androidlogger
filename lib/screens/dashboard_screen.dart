import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/device_snapshot.dart';
import '../providers/device_status_provider.dart';
import '../providers/dropbox_provider.dart';
import '../providers/logging_provider.dart';
import '../services/charging_service.dart';
import '../services/network_service.dart';
import '../utils/date_time_utils.dart';
import '../widgets/live_activity_list.dart';
import '../widgets/logging_control.dart';
import '../widgets/now_builder.dart';
import '../widgets/state_views.dart';
import '../widgets/status_card.dart';
import 'dropbox_screen.dart';
import 'logs_screen.dart';
import 'privacy_screen.dart';
import 'settings_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final LoggingController _logging;

  @override
  void initState() {
    super.initState();
    _logging = context.read<LoggingController>();
    _logging.dashboardVisible = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _logging.noteDashboardOpened();
    });
  }

  @override
  void dispose() {
    _logging.dashboardClosed();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logging = context.watch<LoggingController>();
    final device = context.watch<DeviceStatusController>();
    final dropbox = context.watch<DropboxController>();
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Android Logger'),
        actions: [
          IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, SettingsScreen.route),
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      bottomNavigationBar: LoggingControl(
        isLogging: logging.isLogging,
        syncing: dropbox.status.isUploading || dropbox.busy,
        onStart: () => logging.startLogging(),
        onStop: () => logging.stopLogging(),
        onViewLogs: () => Navigator.pushNamed(context, LogsScreen.route),
        onSync: () {
          Navigator.pushNamed(
            context,
            DropboxScreen.route,
            arguments: dropbox.connected ? 'sync' : null,
          );
        },
      ),
      body: SafeArea(
        child: ListView(
          key: const Key('dashboardList'),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Real-Time Device Activity Monitor',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (device.offline)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: OfflineBanner(
                  message:
                      "You're offline. Logs will continue to be stored locally.",
                ),
              )
            else if (device.network?.internetReachable == false)
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: OfflineBanner(
                  message:
                      'No internet access. Local logging continues. Dropbox sync is unavailable.',
                ),
              ),
            NowBuilder(
              builder: (context, now) {
                return _LoggingStatus(logging: logging, now: now);
              },
            ),
            const SizedBox(height: 12),
            if (device.loading && !device.hasStatus)
              const LoadingState()
            else if (!device.loading &&
                device.error != null &&
                !device.hasStatus)
              ErrorState(message: device.error!, onRetry: () => device.retry())
            else
              NowBuilder(
                builder: (context, now) =>
                    _StatusGrid(device: device, dropbox: dropbox, now: now),
              ),
            const SizedBox(height: 16),
            LiveActivityList(events: logging.sessionEvents),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, PrivacyScreen.route),
                child: const Text('What is logged?'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoggingStatus extends StatelessWidget {
  const _LoggingStatus({required this.logging, required this.now});

  final LoggingController logging;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = logging.isLogging;
    final started = logging.sessionStartedAt;
    final count = logging.sessionCount;
    final countLabel = '$count ${count == 1 ? 'Event' : 'Events'}';
    return Semantics(
      key: const Key('loggingStatus'),
      liveRegion: true,
      label: active
          ? 'Logging active. $countLabel'
          : 'Logging stopped. $countLabel',
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                active ? '● LOGGING ACTIVE' : '○ LOGGING STOPPED',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                started == null
                    ? 'Logging has not started'
                    : startedLabel(started, now),
              ),
              const SizedBox(height: 4),
              Text(countLabel, style: theme.textTheme.headlineSmall),
              Text('Stored: ${logging.events.length}'),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusGrid extends StatelessWidget {
  const _StatusGrid({
    required this.device,
    required this.dropbox,
    required this.now,
  });

  final DeviceStatusController device;
  final DropboxController dropbox;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final battery = device.battery;
    final network = device.network;
    final width = MediaQuery.sizeOf(context).width;
    final columns = width >= 700 ? 4 : (width >= 360 ? 2 : 1);
    final cardWidth = (width - 32 - (12 * (columns - 1))) / columns;
    final lastSync = dropbox.status.lastSuccess;
    final cards = [
      StatusCard(
        icon: battery.charge == ChargeState.charging
            ? Icons.battery_charging_full
            : Icons.battery_full,
        title: 'Battery',
        value: battery.level == null ? 'Unavailable' : '${battery.level}%',
        subtitle: ChargingService.stateLabel(battery),
        semanticsLabel: battery.level == null
            ? 'Battery unavailable. ${ChargingService.stateLabel(battery)}'
            : 'Battery ${battery.level} percent. ${ChargingService.stateLabel(battery)}',
      ),
      StatusCard(
        icon: network == null || network.isOffline
            ? Icons.wifi_off
            : Icons.wifi,
        title: 'Network',
        value: network == null
            ? 'Unavailable'
            : NetworkService.transportLabel(network),
        subtitle: network == null
            ? 'Internet status unknown'
            : NetworkService.internetLabel(network),
        semanticsLabel: network == null
            ? 'Network unavailable'
            : '${NetworkService.transportLabel(network)}. ${NetworkService.internetLabel(network)}',
      ),
      StatusCard(
        icon: Icons.power,
        title: 'Charging',
        value: ChargingService.connectionLabel(battery),
        subtitle: ChargingService.stateLabel(battery),
        semanticsLabel:
            'Charging ${ChargingService.connectionLabel(battery)}. ${ChargingService.stateLabel(battery)}',
      ),
      StatusCard(
        icon: dropbox.connected ? Icons.cloud_done : Icons.cloud_off,
        title: 'Dropbox',
        value: dropbox.status.isUploading
            ? 'Uploading'
            : dropbox.connected
            ? 'Connected'
            : 'Not connected',
        subtitle: lastSync == null
            ? 'Last sync: Never'
            : 'Last sync: ${relativeTime(lastSync, now)}',
        semanticsLabel: dropbox.connected
            ? 'Dropbox connected'
            : 'Dropbox not connected',
      ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final card in cards) SizedBox(width: cardWidth, child: card),
      ],
    );
  }
}
