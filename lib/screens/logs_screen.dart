import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/event_type.dart';
import '../models/log_event.dart';
import '../providers/logging_provider.dart';
import '../services/log_storage_service.dart';
import '../utils/date_time_utils.dart';
import '../widgets/dialogs.dart';
import '../widgets/event_card.dart';
import '../widgets/state_views.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  static const route = '/logs';

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  final TextEditingController _search = TextEditingController();
  final Set<EventType> _types = {...EventType.values};
  DateTime? _day;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      context.read<LoggingController>().logAppAction('Logs screen opened');
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked != null) {
      setState(() => _day = picked);
    }
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
        const SnackBar(
          content: Text(
            'Unable to open the share sheet. The export file was saved in app storage.',
          ),
        ),
      );
    }
  }

  Future<void> _clear() async {
    final confirmed = await confirmAction(
      context,
      title: 'Clear logs',
      message:
          'Delete every event stored on this device? This does not delete a file already uploaded to Dropbox.',
      confirmLabel: 'Clear logs',
    );
    if (!confirmed || !mounted) {
      return;
    }
    await context.read<LoggingController>().clear();
  }

  @override
  Widget build(BuildContext context) {
    final logging = context.watch<LoggingController>();
    final visible = LogFilter.apply(
      logging.events,
      LogQuery(text: _search.text, types: _types, day: _day),
    ).reversed.toList();
    final allSelected = _types.length == EventType.values.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Logs (${logging.events.length})'),
        actions: [
          IconButton(
            tooltip: 'Export android_log.txt',
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Clear logs',
            onPressed: _clear,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              key: const Key('logSearch'),
              controller: _search,
              decoration: InputDecoration(
                labelText: 'Search logs',
                hintText: 'Description, type, or time',
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () => setState(_search.clear),
                        icon: const Icon(Icons.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: const Key('filter_all'),
                    label: const Text('ALL'),
                    selected: allSelected,
                    onSelected: (_) {
                      setState(() {
                        _types
                          ..clear()
                          ..addAll(EventType.values);
                      });
                    },
                  ),
                ),
                for (final type in EventType.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      key: Key('filter_${type.name}'),
                      label: Text(type.label),
                      selected: _types.contains(type),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _types.add(type);
                          } else {
                            _types.remove(type);
                          }
                        });
                      },
                    ),
                  ),
                ActionChip(
                  label: Text(
                    _day == null ? 'Any date' : formatShortDate(_day!),
                  ),
                  onPressed: _pickDay,
                ),
                if (_day != null)
                  IconButton(
                    tooltip: 'Clear date filter',
                    onPressed: () => setState(() => _day = null),
                    icon: const Icon(Icons.close),
                  ),
              ],
            ),
          ),
          if (logging.skippedLines > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                '${logging.skippedLines} damaged log lines were skipped.',
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => context.read<LoggingController>().reload(),
              child: _buildList(logging, visible),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(LoggingController logging, List<LogEvent> visible) {
    if (logging.loading) {
      return const LoadingState(message: 'Loading logs...');
    }
    if (logging.loadError != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          ErrorState(
            key: const Key('logsError'),
            message: logging.loadError!,
            onRetry: () => context.read<LoggingController>().reload(),
          ),
        ],
      );
    }
    if (logging.events.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          EmptyState(
            key: Key('emptyLogs'),
            message:
                'No events recorded yet.\n\nStart logging to see\nactivity here.',
          ),
        ],
      );
    }
    if (visible.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [EmptyState(message: 'No events match your search.')],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: EventCard(event: visible[index]),
        );
      },
    );
  }
}
